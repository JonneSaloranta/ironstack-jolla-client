.pragma library
// The AI assistant (IronStack apps.assistant, API assistant/...). Pure
// helpers; the pages fetch.

// A reply is still being written.
function isWorking(message) {
    return !!message && message.role === "assistant" && (message.status === "pending" || message.status === "running")
}

// The newest message still being written, or null.
function workingMessage(messages) {
    for (var i = (messages || []).length - 1; i >= 0; i--) {
        if (isWorking(messages[i]))
            return messages[i]
    }
    return null
}

// `message` in place of the one with its id.
function replaceMessage(messages, message) {
    return (messages || []).map(function(m) { return m.id === message.id ? message : m })
}

function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// The assistant writes Markdown; Silica labels take a little HTML
// (StyledText). Headings and **bold** become bold, *italic* italic,
// `code` stays as typed, "- " and "* " items get a bullet, and lines keep
// their breaks. Anything else shows as plain text.
function styled(markdown) {
    var lines = escapeHtml(markdown || "").split("\n")
    return lines.map(function(line) {
        var heading = /^\s{0,3}#{1,6}\s+(.*)$/.exec(line)
        if (heading)
            return "<b>" + heading[1] + "</b>"
        line = line.replace(/^(\s*)[-*]\s+/, function(all, indent) { return indent.replace(/ /g, "&nbsp;") + "• " })
        line = line.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
        line = line.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
        line = line.replace(/`([^`]+)`/g, "$1")
        return line
    }).join("<br>")
}

// Open proposals ("pending") can be created or dismissed.
function isOpen(proposal) {
    return !!proposal && proposal.status === "pending"
}
