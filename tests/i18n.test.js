const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const OmarchyMenu = require("../core/OmarchyMenu.js")

const dir = path.join(__dirname, "../i18n")
const read = name => JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"))
const en = read("en.json")

test("every catalog is flat JSON over the English keys, keeping %1 and plural forms", () => {
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith(".json"))) {
    const catalog = read(file)
    for (const [key, value] of Object.entries(catalog)) {
      assert.ok(key in en, `${file}: "${key}" is not in en.json`)
      const forms = typeof value === "string" ? [value] : Object.values(value)
      if (typeof value !== "string") assert.ok(typeof value.other === "string", `${file}: "${key}" has no "other" form`)
      for (const form of forms) {
        assert.equal(typeof form, "string")
        assert.ok(form.length > 0, `${file}: "${key}" is empty`)
        if (key.includes("%1")) assert.ok(form.includes("%1"), `${file}: "${key}" lost its %1`)
      }
    }
  }
})

test("every string the window translates has an English entry", () => {
  const ui = path.join(__dirname, "../ui")
  const missing = []
  for (const file of fs.readdirSync(ui).filter(f => f.endsWith(".qml"))) {
    const source = fs.readFileSync(path.join(ui, file), "utf8")
    for (const m of source.matchAll(/window\.tr\("((?:[^"\\]|\\.)*)"\)/g)) if (!(m[1] in en)) missing.push(`${file}: ${m[1]}`)
  }
  assert.deepEqual(missing, [])
})

test("Omarchy's menu catalog translates shipped rows and keeps the English label findable", () => {
  const items = OmarchyMenu.parse(JSON.stringify({ appearance: { label: "Appearance" }, "appearance.theme": { label: "Theme", action: "x" } })).items
  const out = OmarchyMenu.applyTranslations(items, { appearance: { label: "Udseende" }, ignored: "x" })
  const appearance = out.find(i => i.id === "appearance")
  assert.equal(appearance.label, "Udseende")
  assert.ok(appearance.aliases.includes("Appearance"))
  assert.equal(out.find(i => i.id === "appearance.theme").label, "Theme")
  assert.equal(items.find(i => i.id === "appearance").label, "Appearance", "input rows are not changed")
  assert.deepEqual(OmarchyMenu.applyTranslations(items, null), items)
})
