// let state = ...;
// const state_to_ui = ...;

function create_elem(elem) {
  switch (elem.variant) {
    case 0:
      const button = document.createElement("button")
      button.onclick = () => {
        state = elem.field1(state)
        render_ui()
      }
      for (const child of elem.field0) {
        button.appendChild(create_elem(child))
      }
      return button
    case 1:
      const div = document.createElement("div")
      div.setAttribute("style", elem.field0)
      for (const child of elem.field1) {
        div.appendChild(create_elem(child))
      }
      return div
    case 2:
      return document.createTextNode(elem.field0)
  }
}

function render_ui() {
  ui = state_to_ui(state)
  document.body.innerHTML = ""
  for (const elem of ui) {
    document.body.appendChild(create_elem(elem))
  }
}

window.onload = () => {
  render_ui()
}
