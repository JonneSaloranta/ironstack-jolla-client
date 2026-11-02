.pragma library
// Long built-in texts (program descriptions, exercise and stretch
// instructions) as the web shows them. Separate from store.js so the big
// catalog is loaded only by the pages that show these texts.
.import "content_texts.js" as Texts
.import "store.js" as Store

function contentText(value) {
    if (!value)
        return value || ""
    var texts = Texts.catalog[Store.contentLanguage()]
    return (texts && texts[value]) || value
}
