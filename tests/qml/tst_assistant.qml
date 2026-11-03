import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/assistant.js" as Assistant

TestCase {
    name: "Assistant"

    function test_working() {
        var messages = [{ id: 1, role: "user", status: "done" }, { id: 2, role: "assistant", status: "running" }]
        verify(Assistant.isWorking(messages[1]))
        verify(!Assistant.isWorking(messages[0]))
        compare(Assistant.workingMessage(messages).id, 2)
        compare(Assistant.workingMessage([{ id: 3, role: "assistant", status: "done" }]), null)
        var replaced = Assistant.replaceMessage(messages, { id: 2, role: "assistant", status: "done", text: "Hi" })
        compare(replaced[1].text, "Hi")
        compare(messages[1].status, "running")
    }

    function test_styled() {
        compare(Assistant.styled("## Plan\n- **Squat** 5x5\n- *easy* day"),
                "<b>Plan</b><br>• <b>Squat</b> 5x5<br>• <i>easy</i> day")
        compare(Assistant.styled("a < b & `c`"), "a &lt; b &amp; c")
        compare(Assistant.styled(""), "")
    }

    function test_isOpen() {
        verify(Assistant.isOpen({ status: "pending" }))
        verify(!Assistant.isOpen({ status: "accepted" }))
    }
}
