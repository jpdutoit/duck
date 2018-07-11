module duck.compiler.visitors.treeshaker;

import duck.compiler.context;
import duck.compiler.ast;
import duck.compiler.visitors;

struct TreeShaker {
  Context context;
  bool[Decl] referencedDecls;

  this(Context context) {
    this.context = context;
  }

  bool isReferenced(Decl d) {
    return !context.options.treeshake || (d in referencedDecls) !is null;
  }

  auto declarations() {
    return referencedDecls.byKey();
  }

  void addRoot(Decl decl) {
    if (!decl || decl in referencedDecls) return;
    referencedDecls[decl] = true;
    decl.visit!(
      (CallableDecl decl) {
        this.addRoot(decl.parent);
        if (decl.callableBody)
          this.addRoot(decl.callableBody);
        else
          this.addRoot(decl.returnExpr);
      },
      (VarDecl decl) {
        this.addRoot(decl.valueExpr);
        this.addRoot(decl.parent);
      },
      (ParameterDecl decl) { },
      (StructDecl decl) { },
      (AliasDecl decl) { },
      (ModuleDecl decl) {
        if (auto os = (decl.members.lookup("tick"))) {
          if (os.length > 0)
            this.addRoot(os[0]);
        }
        // We don't care about the other fields or functions,
        // will only mark them as referenced
        // if they are used by some actual code somewhere
      },
      (ImportDecl decl) { },
      (TypeDecl decl) { }
    );
  }

  void addRoot(Node root) {
    if (!context.options.treeshake) return;
    if (!root) return;
    root.traverse!(
      (RefExpr r) {
        this.addRoot(r.decl);
        return Traverse.proceed;
      },
      (Decl decl) {
        this.addRoot(decl);
        return Traverse.skip;
      }
    );
  }
}
