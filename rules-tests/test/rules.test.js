// Extra Spice #2 (Rules Unit Tester): the security rules, tested as their
// own layer against the Firestore emulator. Run from this folder:
//   npm install && npm test
// `npm test` starts the emulator, runs this file, and stops the emulator.
import { readFileSync } from "node:fs";
import { after, afterEach, before, describe, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

const serverTime = () => firebase.firestore.FieldValue.serverTimestamp();
const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");

let env;
const db = (uid) =>
  uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();

/** Seed documents with the rules switched off (like an admin). */
async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(path).set(data);
  });
}

const aliceMessage = {
  text: "Hello from Alice",
  authorUid: "alice",
  authorName: "Alice Adams",
  createdAt: firebase.firestore.Timestamp.fromDate(new Date("2026-11-21T15:00:00Z")),
};

const aliceRecord = () => ({
  uid: "alice",
  firstName: "Alice",
  lastName: "Adams",
  role: "student",
  registrationDateTime: serverTime(),
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-hw02",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
      host,
      port: Number(port),
    },
  });
});

afterEach(async () => env.clearFirestore());
after(async () => env.cleanup());

describe("messages: read", () => {
  test("signed-out read is denied", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(db(null).collection("messages").get());
    await assertFails(db(null).doc("messages/m1").get());
  });

  test("any signed-in user can read the board", async () => {
    await seed("messages/m1", aliceMessage);
    await assertSucceeds(db("bob").collection("messages").orderBy("createdAt").get());
  });
});

describe("messages: create", () => {
  const ok = (uid) => ({
    text: "Hi board",
    authorUid: uid,
    authorName: "Some Name",
    createdAt: serverTime(),
  });

  test("correct author with server timestamp is allowed", async () => {
    await assertSucceeds(db("alice").doc("messages/new1").set(ok("alice")));
  });

  test("forged authorUid is denied", async () => {
    await assertFails(db("alice").doc("messages/new1").set(ok("bob")));
  });

  test("signed-out create is denied", async () => {
    await assertFails(db(null).doc("messages/new1").set(ok("alice")));
  });

  test("device-clock createdAt is denied", async () => {
    await assertFails(
      db("alice").doc("messages/new1").set({ ...ok("alice"), createdAt: new Date("2001-01-01") }),
    );
  });

  test("empty or whitespace-only text is denied", async () => {
    await assertFails(db("alice").doc("messages/new1").set({ ...ok("alice"), text: "   " }));
  });

  test("text over 500 characters is denied", async () => {
    await assertFails(db("alice").doc("messages/new1").set({ ...ok("alice"), text: "x".repeat(501) }));
  });

  test("extra fields are denied", async () => {
    await assertFails(db("alice").doc("messages/new1").set({ ...ok("alice"), pinned: true }));
  });
});

describe("messages: update", () => {
  test("owner can edit text with editedAt = server time", async () => {
    await seed("messages/m1", aliceMessage);
    await assertSucceeds(
      db("alice").doc("messages/m1").update({ text: "Edited", editedAt: serverTime() }),
    );
  });

  test("another signed-in user cannot edit", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(
      db("bob").doc("messages/m1").update({ text: "Hacked", editedAt: serverTime() }),
    );
  });

  test("owner cannot change authorUid", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(db("alice").doc("messages/m1").update({ authorUid: "bob" }));
  });

  test("owner cannot rewrite createdAt", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(
      db("alice").doc("messages/m1").update({ text: "x", editedAt: serverTime(), createdAt: serverTime() }),
    );
  });

  test("owner cannot blank the text", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(db("alice").doc("messages/m1").update({ text: "", editedAt: serverTime() }));
  });
});

describe("messages: delete", () => {
  test("owner can delete", async () => {
    await seed("messages/m1", aliceMessage);
    await assertSucceeds(db("alice").doc("messages/m1").delete());
  });

  test("another signed-in user cannot delete", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(db("bob").doc("messages/m1").delete());
  });

  test("signed-out delete is denied", async () => {
    await seed("messages/m1", aliceMessage);
    await assertFails(db(null).doc("messages/m1").delete());
  });
});

describe("users/{uid}: private record", () => {
  test("owner creates the record with exactly the five fields", async () => {
    await assertSucceeds(db("alice").doc("users/alice").set(aliceRecord()));
  });

  test("creating someone else's record is denied", async () => {
    await assertFails(db("bob").doc("users/alice").set(aliceRecord()));
  });

  test("a missing field or an extra field is denied", async () => {
    const { role, ...missingRole } = aliceRecord();
    void role;
    await assertFails(db("alice").doc("users/alice").set(missingRole));
    await assertFails(db("alice").doc("users/alice").set({ ...aliceRecord(), isAdmin: true }));
  });

  test("an unknown role is denied (roles never grant access)", async () => {
    await assertFails(db("alice").doc("users/alice").set({ ...aliceRecord(), role: "admin" }));
  });

  test("owner reads own record; others and signed-out users cannot", async () => {
    await seed("users/alice", { ...aliceRecord(), registrationDateTime: new Date() });
    await assertSucceeds(db("alice").doc("users/alice").get());
    await assertFails(db("bob").doc("users/alice").get());
    await assertFails(db(null).doc("users/alice").get());
  });

  test("owner cannot reset the registration time or change role", async () => {
    await seed("users/alice", { ...aliceRecord(), registrationDateTime: new Date() });
    await assertFails(db("alice").doc("users/alice").set(aliceRecord()));
    await assertFails(db("alice").doc("users/alice").update({ role: "instructor" }));
    await assertSucceeds(db("alice").doc("users/alice").update({ firstName: "Alicia" }));
  });

  test("records cannot be deleted from the client", async () => {
    await seed("users/alice", { ...aliceRecord(), registrationDateTime: new Date() });
    await assertFails(db("alice").doc("users/alice").delete());
  });

  test("prefs are owner-only", async () => {
    await assertSucceeds(db("alice").doc("users/alice/prefs/notifications").set({ optIn: true }));
    await assertFails(db("bob").doc("users/alice/prefs/notifications").get());
  });
});
