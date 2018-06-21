module duck.compiler.semantic.overloads;

import duck.compiler;
import duck.compiler.visitors;
import duck.compiler.semantic.helpers;

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
  static Cost intToFloat() { return Cost(1); }
  static Cost staticArrayToDynamic() { return Cost(2); }
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

  if (auto property = type.as!PropertyType) {
    auto getters = lookup(property, "get");
    if (getters.count == 1) {
      if (auto getter = getters.front.type.as!FunctionType) {
        if (getter.parameterTypes.length == 0)
          return Cost.implicitCall + coercionCost(getter.returnType, target);
      }
      return coercionCost(getters.front.type, target);
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
    auto output = lookup(moduleType, "output");
    if (output.count == 1) {
      return Cost.implicitOutput + coercionCost(output.front.type, target);
    }
  }

  // Coerce int by automatically converting it to float
  if (type.as!IntegerType && target.as!FloatType) {
    return Cost.intToFloat;
  }

  // Coerce static array by automatically converting it to dynamic arrayDecl
  if (auto sourceArray = type.as!StaticArrayType)
  if (auto targetArray = target.as!ArrayType)
  if (sourceArray.elementType.isSameType(targetArray.elementType)) {
    return Cost.staticArrayToDynamic;
  }

  return Cost.infinity;
}

Cost coercionCost(Expr[] args, Type[] targetTypes) {
  if (args.length != targetTypes.length) return Cost.infinity;

  Cost cost;
  size_t len = args.length;
  for (int i = 0; i < len; ++i) {
    if (!cost) return cost;
    cost = cost + coercionCost(args[i].type, targetTypes[i]);
  }
  return cost;
}

auto findBestOverload(R)(R decls, Expr[] args, CallableDecl[]* viable = null)
if (isDeclRange!R)
{
  Cost lowestCost = Cost.max;
  int matches = 0;
  CallableDecl[32] overloads;
  ElementType!R best;
  foreach(candidate; decls) {
    if (auto callable = candidate.as!CallableDecl) {
      Cost cost = coercionCost(args, callable.type.parameterTypes);
      //debug(Semantic) log("=> Cost:", cost, "for", args.map(a => a.describe()), "to", callable.type.parameters.describe);
      if (cost <= lowestCost) {
        if (cost != lowestCost) {
          lowestCost = cost;
          matches = 0;
          best = candidate;
        }
        overloads[matches++] = callable;
      }
    }
  }

  if (viable) {
    (*viable).length = 0;
  }

  if (matches == 1) {
    debug(Semantic) log("=>", matches, "match at cost", lowestCost);
    return best;
  }
  if (matches > 1) {
    debug(Semantic) log("=>", matches, "match at cost", lowestCost);
    if (viable) {
      (*viable).reserve(matches);
      foreach (overload; overloads[0..matches]) *viable ~= overload;
    }
    return ElementType!R.init;
  }
  debug(Semantic) log("=> 0 matches");
  return ElementType!R.init;
}
