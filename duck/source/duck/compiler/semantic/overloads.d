module duck.compiler.semantic.overloads;

import duck.compiler.semantic.helpers;
import duck.compiler.ast;
import duck.compiler.scopes;
import duck.compiler.types;
import duck.compiler.dbg;

// Type coercion cost
struct Cost {
  int cost;

  string toString() {
    if (!this) return "inf";
    import std.conv;
    return cost.to!string;
  }
  static Cost max()  { return Cost(int.max-1); }
  static Cost infinity() { return Cost(int.max); }
  static Cost zero() { return Cost(0); }
  static Cost implicitCall() { return Cost(100); }
  static Cost implicitOutput() { return Cost(10000); }
  static Cost implicitConstruct() { return Cost(10000); }

  bool opCast(T: bool)() {
    return cost != int.max;
  }
  Cost opBinary(string op : "+")(auto ref Cost other) {
    if (!this) return this;
    if (!other) return other;
    return Cost(cost + other.cost);
  }
  int opCmp(Cost other) {
    return cost - other.cost;
  }
  bool opEquals(Cost other) {
    return cost == other.cost;
  }
}

Cost coercionCost(Type type, Type target) {
  if (!type || !target) return Cost.infinity;
  if (type.isSameType(target)) return Cost.zero;

  // Coerce an overload set by automatically calling it with not arguments
  if (auto overloadSetType = cast(OverloadSetType)type) {
    if (overloadSetType.overloadSet.decls.length == 1) {
      auto functionType = cast(FunctionType)overloadSetType.overloadSet.decls[0].type;
      auto returnType = functionType.returnType;
      return Cost.implicitCall + coercionCost(returnType, target);
    }
  }
  // Coerce type by constructing instance of that type
  if (auto metaType = cast(MetaType)type) {
    if (auto moduleType = cast(ModuleType)metaType.type) {
      return Cost.implicitConstruct + coercionCost(moduleType, target);
    }
  }
  // Coerce module by automatically reference field output
  if (auto moduleType = cast(ModuleType)type) {
    auto output = moduleType.decl.decls.lookup("output");
    if (output) {
      return Cost.implicitOutput + coercionCost(output.getResultType, target);
    }
  }
  return Cost.infinity;
}

Cost coercionCost(Type[] args, Type contextType, CallableDecl F) {
  if (F.contextType !is null) {
    if (contextType is null) {
      return Cost.infinity;
    }
    Type targetContextType = F.contextType.getTypeDecl.declaredType;
    if (contextType != targetContextType) {
      return Cost.infinity;
    }
  }

  Cost cost;
  if (args.length != F.parameterTypes.length) return Cost.infinity;

  int score = 0;
  size_t len = args.length;
  for (int i = 0; i < len; ++i) {
    if (!cost) return cost;

    Type paramType = F.parameterTypes[i].getTypeDecl.declaredType;
    Type argType  = args[i];
    cost = cost + coercionCost(argType, paramType);
  }
  return cost;
}


/*
F1 is determined to be a better function than F2 if implicit conversions for
all arguments of F1 are not worse than the implicit conversions for all arguments of F2, and
1) there is at least one argument of F1 whose implicit conversion is better than the corresponding implicit conversion for that argument of F2
2) or. if not that, (only in context of non-class initialization by conversion), the standard conversion sequence from the return type of F1 to the type being initialized is better than the standard conversion sequence from the return type of F2
3) or, if not that, F1 is a non-template function while F2 is a template specialization
4) or, if not that, F1 and F2 are both template specializations and F1 is more specialized according to the partial ordering rules for template specializations
*/



CallableDecl findBestOverload(OverloadSet os, Expr contextExpr, TupleExpr args, CallableDecl[]* viable) {
  assert(args.type.as!TupleType, "Internal error: Expected args to have tuple type");
  auto elementTypes = args.type.as!TupleType().elementTypes;
  auto contextType = contextExpr ? contextExpr.type : null;

  Cost lowestCost = Cost.max;
  int matches = 0;
  CallableDecl[32] overloads;
  foreach(callable; os.decls) {

    Cost cost = elementTypes.coercionCost(contextType, callable);
    debug(Semantic) log("=> Cost:", cost, "for", args.type.describe(), "to", callable.type.parameters.describe);
    if (cost <= lowestCost) {
      if (cost != lowestCost) {
        lowestCost = cost;
        matches = 0;
      }
      overloads[matches++] = callable;
    }
  }

  if (matches == 1) {
    debug(Semantic) log("=>", matches, "match at cost", lowestCost);
    return overloads[0];
  }
  if (matches > 1) {
    debug(Semantic) log("=>", matches, "match at cost", lowestCost);
    if (viable) {
      (*viable).reserve(matches);
      foreach (overload; overloads[0..matches]) *viable ~= overload;
    }
    return null;
  }
  debug(Semantic) log("=> 0 matches");
  return null;
}
