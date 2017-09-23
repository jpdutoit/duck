module duck.compiler.visitors.treeshaker;

import duck.compiler.ast;
import duck.compiler.visitors;

struct TreeShaker {
  bool[Decl] referencedDecls;

  this(Node root) {
    addRoot(root);
  }

  bool isReferenced(Decl d) {
    return (d in referencedDecls) !is null;
  }

  auto declarations() {
    return referencedDecls.byKey();
  }

  void addRoot(Decl decl) {
    if (!decl || decl in referencedDecls) return;
    referencedDecls[decl] = true;
    decl.visit!(
      (CallableDecl decl) {
        this.addRoot(decl.parentDecl);
        if (decl.callableBody)
          this.addRoot(decl.callableBody);
        else
          this.addRoot(decl.returnExpr);
      },
      (VarDecl decl) {
        this.addRoot(decl.valueExpr);
        this.addRoot(decl.parentDecl);
      },
      (ParameterDecl decl) { },
      (StructDecl decl) { },
      (ModuleDecl decl) {
        if (auto os = cast(OverloadSet)(decl.members.lookup("tick"))) {
          this.addRoot(os.decls[0]);
        }
        // We don't care about the other fields or functions,
        // will only mark them as referenced
        // if they are used by some actual code somewhere
      },
      (TypeDecl decl) { }
    );
  }

  void addRoot(Node root) {
    if (!root) return;
    root.traverse!(
      (RefExpr r) => this.addRoot(r.decl),
      (DeclStmt stmt) {
        if (cast(VarDecl)(stmt.decl))
          this.addRoot(stmt.decl);
      }
    );
  }
}