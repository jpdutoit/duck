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
    treeShaker.addRoot(main.stmts);
    findFieldDependencies(main.stmts);
  }

  CallableDecl hasTick(ModuleDecl mod) {
    if (auto os = mod.members.lookup("tick")) {
      if (os.length > 0)
        return os[0].as!CallableDecl;
    }
    return null;
  }

  bool isDynamicField(VarDecl field) {
    if (!treeShaker.isReferenced(field)) return false;
    return field && field.parent && field.parent.declaredType.as!ModuleType && !field.type.as!ModuleType && !field.type.as!PropertyType && (field in fieldDependencyCount) !is null;
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
      (RefExpr e) {
        if (e.decl.parent.as!ModuleDecl)
          return e.decl.as!VarDecl;

        return null;
      }
    );
  }

  auto findContextModules(Node node) {
    return node.traverseCollect!(
      (RefExpr e) {
        if (e.context) {
          if (auto moduleType = e.context.type.as!ModuleType) {
            return moduleType.decl;
          }
          if (auto propertyType = e.type.as!PropertyType)
            if (auto moduleType = propertyType.decl.parent.declaredType.as!ModuleType) {
              return moduleType.decl;
            }
        }
        return null;
    });
  }

  final void findFieldDependencies(Node node) {
    import std.algorithm: max;
    node.traverse!(
      (Decl decl) {
        if (!treeShaker.isReferenced(decl)) return Traverse.skip;
        return Traverse.proceed;
      },
      (PipeExpr e) {
        if (auto field = findField(e.right)) {
          int dependencies = cast(int)findContextModules(e.left).length;
          if (dependencies > 0) {
            auto existing = field in fieldDependencyCount;
            if (existing) *existing = max(*existing, dependencies);
            else fieldDependencyCount[field] = dependencies;
          }
        }
        return Traverse.proceed;
    });
  }
}
