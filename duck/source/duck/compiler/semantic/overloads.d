module duck.compiler.semantic.overloads;

import duck.compiler.semantic.helpers;
import duck.compiler.ast;
import duck.compiler.scopes;
import duck.compiler.types;

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
  static Cost implicitOutput() { return Cost(1000); }

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
    Type targetContextType = F.contextType.getTypeDecl.declType;
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

    Type paramType = F.parameterTypes[i].getTypeDecl.declType;
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
  Cost lowestCost = Cost.max;
  int matches = 0;
  CallableDecl[32] overloads;
  foreach(decl; os.decls) {

    auto functionType = cast(FunctionType)decl.declType;

    assert(cast(TupleType)args.exprType !is null, "Internal error: Expected args to have tuple type");
    Cost cost = ((cast(TupleType)args.exprType).elementTypes).coercionCost(contextExpr ? contextExpr.exprType : null, decl);
    debug(Semantic) log("=> Cost:", cost, "for", args.exprType.describe(), "to", functionType.parameters.describe);
    if (cost <= lowestCost) {
      if (cost != lowestCost) {
        lowestCost = cost;
        matches = 0;
      }
      overloads[matches++] = decl;
    }
  }

  if (matches == 1) {
    debug(Semantic) log("=>", matches, "match at cost", lowestCost);
    return overloads[0];
  }
  if (matches > 1) {
    debug(Semantic) log("=>", matches, "match at cost", lowestCost);
    foreach (overload; overloads) *viable ~= overload;
    return null;
  }
  debug(Semantic) log("=> 0 matches");
  return null;
}
