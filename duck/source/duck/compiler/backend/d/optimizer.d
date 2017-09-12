module duck.compiler.backend.d.optimizer;

import duck.compiler.ast;
import duck.compiler.visitors;
import duck.compiler.semantic.helpers;
import duck.compiler.types;
import duck.compiler.visitors.treeshaker;
import duck.compiler.dbg;

class Optimizer {
  int[FieldDecl] fieldDependencyCount;
  TreeShaker treeShaker;

  this(Library main) {
    findFieldDependencies(main.stmts);
    treeShaker.addRoot(main.stmts);
  }

  CallableDecl hasTick(ModuleDecl mod) {
    if (auto os = mod.members.lookup("tick").as!OverloadSet) {
      return os.decls[0];
    }
    return null;
  }

  bool isDynamicField(FieldDecl field) {
    //TODO: Reenable this at a later stage once it works correctly.
    return field && field.parentDecl.declaredType.isModule && !field.type.isModule;
    //return field && field.parentDecl.declaredType.isModule && !field.type.isModule && (field in fieldDependencyCount) !is null;
  }

  bool hasDynamicFields(ModuleDecl mod) {
    if (hasTick(mod)) return true;
    foreach(field; mod.fields.as!FieldDecl) {
      if (isDynamicField(field))
        return true;
    }
    return false;
  }

  bool isReferenced(Decl decl) {
    return treeShaker.isReferenced(decl);
  }

  auto findField(Node node) {
    return node.traverseFind!(
      (RefExpr e) => e.decl.as!FieldDecl
    );
  }

  auto findContextModules(Node node) {
    return node.traverseCollect!(
      (RefExpr e) {
        if (e.context)
        if (auto moduleType = e.context.type.as!ModuleType) {
          return moduleType.decl;
        }
        return null;
    });
  }

  void findFieldDependencies(Node node) {
    import std.algorithm: max;
    node.traverse!(
      (PipeExpr e) {
        if (auto field = findField(e.right)) {
          int dependencies = cast(int)findContextModules(e.left).length;
          if (dependencies > 0) {
            auto existing = field in fieldDependencyCount;
            if (existing) *existing = max(*existing, dependencies);
            else fieldDependencyCount[field] = dependencies;
          }
        }
    });
  }
}
