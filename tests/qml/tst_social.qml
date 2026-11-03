import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/social.js" as Social

TestCase {
    name: "Social"

    function test_mergeMessages() {
        var a = [{ id: 1 }, { id: 3 }]
        var merged = Social.mergeMessages(a, [{ id: 3 }, { id: 4 }, { id: 2 }])
        compare(merged.map(function(m) { return m.id }), [1, 2, 3, 4])
        compare(a.length, 2)
        compare(Social.lastId(merged), 4)
        compare(Social.lastId([]), null)
        compare(Social.mergeMessages(null, null).length, 0)
    }

    function test_attention() {
        compare(Social.attention({ friends: [{ unread: 2 }, { unread: 0 }], groups: [{ unread: 1 }],
                                   pending_friend_requests: 1, pending_group_invites: 1 }), 5)
        compare(Social.attention(null), 0)
    }

    function test_startsDay() {
        var messages = [{ created_at: "2026-11-02T10:00:00Z" }, { created_at: "2026-11-02T10:05:00Z" },
                        { created_at: "2026-11-04T10:00:00Z" }]
        verify(Social.startsDay(messages, 0))
        verify(!Social.startsDay(messages, 1))
        verify(Social.startsDay(messages, 2))
    }

    function test_requestsFor() {
        var r = Social.requestsFor([
            { id: 1, from_user: { username: "a" }, to_user: { username: "me" }, status: "pending" },
            { id: 2, from_user: { username: "me" }, to_user: { username: "b" }, status: "pending" },
            { id: 3, from_user: { username: "c" }, to_user: { username: "me" }, status: "accepted" }
        ], "me")
        compare(r.incoming.length, 1)
        compare(r.incoming[0].id, 1)
        compare(r.outgoing[0].id, 2)
    }

    function test_canManage() {
        verify(Social.canManage("owner"))
        verify(Social.canManage("admin"))
        verify(!Social.canManage("member"))
    }
}
