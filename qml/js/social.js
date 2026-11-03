.pragma library
// Friends, groups and messages (IronStack apps/social, API social/...).
// Pure helpers; the pages fetch.

// `newer` messages added after `messages` (both oldest first), each id
// once - a poll can overlap a reply to a send.
function mergeMessages(messages, newer) {
    var seen = {}
    var result = (messages || []).slice()
    result.forEach(function(m) { seen[m.id] = true })
    ;(newer || []).forEach(function(m) {
        if (!seen[m.id]) {
            seen[m.id] = true
            result.push(m)
        }
    })
    return result.sort(function(a, b) { return a.id - b.id })
}

// The id to poll after: the newest message's, or null for none.
function lastId(messages) {
    return messages && messages.length ? messages[messages.length - 1].id : null
}

// Unread messages and pending requests and invites, from
// social/conversations/ - what the menu shows.
function attention(conversations) {
    if (!conversations)
        return 0
    var count = (conversations.pending_friend_requests || 0) + (conversations.pending_group_invites || 0)
    ;(conversations.friends || []).concat(conversations.groups || []).forEach(function(c) {
        count += c.unread || 0
    })
    return count
}

// Whether a message starts a new day in the thread (shown as a heading).
function startsDay(messages, index) {
    if (index === 0)
        return true
    return new Date(messages[index].created_at).toDateString()
            !== new Date(messages[index - 1].created_at).toDateString()
}

// Friend requests split by direction: { incoming, outgoing } for the
// username `me` (profile/ has no user id).
function requestsFor(requests, me) {
    var result = { incoming: [], outgoing: [] }
    ;(requests || []).forEach(function(r) {
        if (r.status !== "pending")
            return
        if (r.to_user && r.to_user.username === me)
            result.incoming.push(r)
        else
            result.outgoing.push(r)
    })
    return result
}

// Can `role` (owner/admin/member) manage the group's members and invites?
function canManage(role) {
    return role === "owner" || role === "admin"
}

// The signed-in username (profile/), to tell own messages and requests
// apart; read once.
var me = ""

function ensureMe(api, done) {
    if (me)
        return done(true, "")
    api.request("GET", "profile/", null, function(ok, status, data, error) {
        if (ok)
            me = data.username || ""
        done(ok, error)
    })
}

// Something changed on another page (a group left, a friend added); the
// friends and groups page reloads.
var changed = false
