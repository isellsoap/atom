StylesElement = require '../src/styles-element'
StyleManager = require '../src/style-manager'

describe "StylesElement", ->
  [element, addedStyleElements, removedStyleElements, updatedStyleElements] = []

  beforeEach ->
    element = new StylesElement
    element.initialize(atom.styles)
    document.querySelector('#jasmine-content').appendChild(element)
    addedStyleElements = []
    removedStyleElements = []
    updatedStyleElements = []
    element.onDidAddStyleElement (element) -> addedStyleElements.push(element)
    element.onDidRemoveStyleElement (element) -> removedStyleElements.push(element)
    element.onDidUpdateStyleElement (element) -> updatedStyleElements.push(element)

  it "renders a style tag for all currently active stylesheets in the style manager", ->
    initialChildCount = element.children.length

    disposable1 = atom.styles.addStyleSheet("a {color: red;}")
    expect(element.children.length).toBe initialChildCount + 1
    expect(element.children[initialChildCount].textContent).toBe "a {color: red;}"
    expect(addedStyleElements).toEqual [element.children[initialChildCount]]

    disposable2 = atom.styles.addStyleSheet("a {color: blue;}")
    expect(element.children.length).toBe initialChildCount + 2
    expect(element.children[initialChildCount + 1].textContent).toBe "a {color: blue;}"
    expect(addedStyleElements).toEqual [element.children[initialChildCount], element.children[initialChildCount + 1]]

    disposable1.dispose()
    expect(element.children.length).toBe initialChildCount + 1
    expect(element.children[initialChildCount].textContent).toBe "a {color: blue;}"
    expect(removedStyleElements).toEqual [addedStyleElements[0]]

  it "orders style elements by priority", ->
    initialChildCount = element.children.length

    atom.styles.addStyleSheet("a {color: red}", priority: 1)
    atom.styles.addStyleSheet("a {color: blue}", priority: 0)
    atom.styles.addStyleSheet("a {color: green}", priority: 2)
    atom.styles.addStyleSheet("a {color: yellow}", priority: 1)

    expect(element.children[initialChildCount].textContent).toBe "a {color: blue}"
    expect(element.children[initialChildCount + 1].textContent).toBe "a {color: red}"
    expect(element.children[initialChildCount + 2].textContent).toBe "a {color: yellow}"
    expect(element.children[initialChildCount + 3].textContent).toBe "a {color: green}"

  it "updates existing style nodes when style elements are updated", ->
    initialChildCount = element.children.length

    atom.styles.addStyleSheet("a {color: red;}", sourcePath: '/foo/bar')
    atom.styles.addStyleSheet("a {color: blue;}", sourcePath: '/foo/bar')

    expect(element.children.length).toBe initialChildCount + 1
    expect(element.children[initialChildCount].textContent).toBe "a {color: blue;}"
    expect(updatedStyleElements).toEqual [element.children[initialChildCount]]

  it "only includes style elements matching the 'context' attribute", ->
    initialChildCount = element.children.length

    atom.styles.addStyleSheet("a {color: red;}", context: 'test-context')
    atom.styles.addStyleSheet("a {color: green;}")

    expect(element.children.length).toBe initialChildCount + 2
    expect(element.children[initialChildCount].textContent).toBe "a {color: red;}"
    expect(element.children[initialChildCount + 1].textContent).toBe "a {color: green;}"

    element.setAttribute('context', 'test-context')

    expect(element.children.length).toBe 1
    expect(element.children[0].textContent).toBe "a {color: red;}"

    atom.styles.addStyleSheet("a {color: blue;}", context: 'test-context')
    atom.styles.addStyleSheet("a {color: yellow;}")

    expect(element.children.length).toBe 2
    expect(element.children[0].textContent).toBe "a {color: red;}"
    expect(element.children[1].textContent).toBe "a {color: blue;}"

  describe "atom-text-editor shadow DOM selector upgrades", ->
    beforeEach ->
      element.setAttribute('context', 'atom-text-editor')
      spyOn(console, 'warn')

    it "removes the ::shadow pseudo-selector from atom-text-editor selectors", ->
      atom.styles.addStyleSheet("""
      atom-text-editor::shadow .class-1, atom-text-editor::shadow .class-2 { color: red; }
      atom-text-editor::shadow > .class-3 { color: yellow; }
      atom-text-editor .class-6 { color: blue; }
      """, {context: 'atom-text-editor'})
      expect(Array.from(element.firstChild.sheet.cssRules).map((r) -> r.selectorText)).toEqual([
        'atom-text-editor .class-1, atom-text-editor .class-2',
        'atom-text-editor > .class-3',
        'atom-text-editor .class-6'
      ])

    it "prepends `--syntax` to all the class name selectors not matching atom-text-editor elements", ->
      atom.styles.addStyleSheet("""
      .class-1 { color: red; }
      .class-2 > .class-3, .class-4.class-5 { color: green; }
      .class-6 atom-text-editor .class-7 { color: yellow; }
      atom-text-editor .class-8, .class-9 { color: blue; }
      #id-1 { color: gray; }
      """, {context: 'atom-text-editor'})
      expect(Array.from(element.firstChild.sheet.cssRules).map((r) -> r.selectorText)).toEqual([
        '.syntax--class-1',
        '.syntax--class-2 > .syntax--class-3, .syntax--class-4.syntax--class-5',
        '.class-6 atom-text-editor .class-7',
        'atom-text-editor .class-8, .syntax--class-9'
        '#id-1'
      ])

    it "upgrades selectors containing .editor-colors", ->
      atom.styles.addStyleSheet(".editor-colors {background: black;}", context: 'atom-text-editor')
      expect(element.firstChild.sheet.cssRules[0].selectorText).toBe ':host'

    it "upgrades selectors containing .editor", ->
      atom.styles.addStyleSheet """
        .editor {background: black;}
        .editor.mini {background: black;}
        .editor:focus {background: black;}
      """, context: 'atom-text-editor'

      expect(element.firstChild.sheet.cssRules[0].selectorText).toBe ':host'
      expect(element.firstChild.sheet.cssRules[1].selectorText).toBe ':host(.mini)'
      expect(element.firstChild.sheet.cssRules[2].selectorText).toBe ':host(:focus)'

    it "defers selector upgrade until the element is attached", ->
      element = new StylesElement
      element.initialize(atom.styles)
      element.setAttribute('context', 'atom-text-editor')

      atom.styles.addStyleSheet ".editor {background: black;}", context: 'atom-text-editor'
      expect(element.firstChild.sheet).toBeNull()

      document.querySelector('#jasmine-content').appendChild(element)
      expect(element.firstChild.sheet.cssRules[0].selectorText).toBe ':host'

    it "does not throw exceptions on rules with no selectors", ->
      atom.styles.addStyleSheet """
        @media screen {font-size: 10px;}
      """, context: 'atom-text-editor'
