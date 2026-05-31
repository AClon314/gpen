import * as vscode from "vscode";

export function activate(context: vscode.ExtensionContext) {
  const disposable = vscode.commands.registerCommand("gpen.openDemo", () => {
    const panel = vscode.window.createWebviewPanel(
      "gpenDemo",
      "GPen",
      vscode.ViewColumn.One,
      { enableScripts: true },
    );

    panel.webview.html = `<!doctype html>
<html lang="en">
  <body>
    <h1>GPen</h1>
    <p>Shared web UI will be mounted here.</p>
  </body>
</html>`;
  });

  context.subscriptions.push(disposable);
}

export function deactivate() {}
