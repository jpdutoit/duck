module duck.compiler.backend.d.optimizer;

import duck.compiler.ast;
import duck.compiler.context;
import duck.compiler.visitors;
import duck.compiler.semantic.helpers;
import duck.compiler.types;
import duck.compiler.visitors.treeshaker;
import duck.compiler.dbg;

class Optimizer {
  int[VarDecl] fieldDependencyCount;
  TreeShaker treeShaker;

  this(Library main, Context context) {
    treeShaker = TreeShaker(context);
    findFieldDependencies(main.stmts);
    treeShaker.addRoot(main.stmts);
  }

  CallableDecl hasTick(ModuleDecl mod) {
    if (auto os = mod.members.lookup("tick")) {
      if (os.length > 0)
        return os[0].as!CallableDecl;
    }
    return null;
  }

  bool isDynamicField(VarDecl field) {
    //TODO: Reenable this at a later stage once it works correctly.
    return field && field.parent && field.parent.declaredType.as!ModuleType && !field.type.as!ModuleType;
    //return field && field.parentDecl.declaredType.as!ModuleType && !field.type.as!ModuleType && (field in fieldDependencyCount) !is null;
  }

  bool hasDynamicFields(ModuleDecl mod) {
    if (hasTick(mod)) return true;
    foreach(field; mod.fields.as!VarDecl) {
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
      (RefExpr e) => e.decl.parent.as!ModuleDecl ? e.decl.as!VarDecl : null
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

  final void findFieldDependencies(Node node) {
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
