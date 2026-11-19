const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

// Event titles, mail subjects and senders are untrusted. A QML Text left on
// its default AutoText would render markup like <img src=...> from them, so
// every Text in the panel and the modal must be plain text.
for (const file of ["Panel.qml", "Modal.qml", "SettingsView.qml"]) {
  test(`every Text in ${file} renders plain text`, () => {
    const source = fs.readFileSync(path.join(__dirname, "..", file), "utf8")
    const blocks = source.split(/\bText \{/).slice(1)

    assert.ok(blocks.length > 0)
    blocks.forEach((block, index) => {
      const body = block.slice(0, block.search(/\n\s*\}/))
      assert.match(body, /textFormat: Text\.PlainText/, `${file} Text #${index + 1} is missing textFormat: Text.PlainText`)
    })
  })
}
