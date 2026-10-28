db = db.getSiblingDB("naijamart");
db.repl_test.drop();
function h(t) { print("\n=== " + t + " ==="); }
function run(title, fn) {
  h(title);
  try { fn(); } catch (e) { print("Not available on this tier, or failed: " + e.message); }
}

run("1. Replica set topology", function () {
  var i = db.hello();
  var members = i.hosts.length;
  var majority = Math.floor(members / 2) + 1;
  print("replica set name   : " + i.setName);
  print("members            : " + members);
  i.hosts.forEach(function (host) { print("  - " + host); });
  print("current primary    : " + i.primary);
  print("connected to       : " + i.me);
  print("majority needed    : " + majority + " of " + members);
  print("failures tolerated : " + (members - majority));
});

run("2. Durable write (majority write concern)", function () {
  var r = db.repl_test.insertOne(
    { _id: "majority-test", note: "written with w:majority" },
    { writeConcern: { w: "majority", j: true } });
  print("acknowledged by a majority of members: " + r.acknowledged);
});

run("3. Read straight after write, from a secondary (eventual consistency)", function () {
  var trials = 30, stale = 0;
  for (var n = 0; n < trials; n++) {
    var id = "probe-" + n;
    db.repl_test.insertOne({ _id: id, n: n }, { writeConcern: { w: 1 } });
    var found = db.repl_test.find({ _id: id }).readPref("secondary").toArray().length;
    if (found === 0) stale++;
  }
  print("writes acknowledged by the primary only (w:1), each read immediately from a secondary");
  print("stale reads (document not yet visible): " + stale + " of " + trials);
});

run("4. Which node served a secondary read", function () {
  var ex = db.repl_test.find({}).readPref("secondary").explain();
  print("served by       : " + ex.serverInfo.host + ":" + ex.serverInfo.port);
  print("current primary : " + db.hello().primary);
  print("(if these differ, a secondary served the read)");
});

db.repl_test.drop();
print("\n(test collection repl_test dropped)");