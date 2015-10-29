module duck.compilers.visitors.codegen;

import duck.compiler.ast, duck.compiler.token, duck.compiler.types;
import duck.compiler.transforms;
import duck.compilers.visitors.expr_to_string;

struct CodeGen {
	alias VisitResultType = String;
  import std.array;
  Appender!String output;

  bool refer = false;
  bool write = true;
  String[] generators;

  void emit(String s) {
    if (write)
      output.put(s);
  }

	String visit(MemberExpr expr) {
    //String owner = expr.expr.accept(this);
    if (refer) {
      if (expr.expr.exprType.kind == GeneratorType.Kind)
        generators ~= (cast(DeclExpr)expr.expr).identifier.value;
      return (cast(DeclExpr)expr.expr).identifier;
    }
      //return "refer(&" ~ owner ~ ", &" ~ owner ~ "._" ~ expr.identifier.value ~ ")";
    else {


//      writefln("%s", expr.expr.exprType);

      //emit("(");
      expr.expr.accept(this);
      emit("._");
      emit(expr.identifier.value);
      //emit(")");
      return null;
	    //return "(" ~ expr.expr.accept(this) ~ "._" ~ expr.identifier.value ~ ")";
    }
	}

	String visit(T)(T expr) if (is(T : LiteralExpr) || is(T : IdentifierExpr)) {
		emit(expr.token.value);
    return null;
	}
	String visit(ArrayLiteralExpr expr) {
		emit("[");
		foreach (i, expr1 ; expr.exprs) {
			if (i != 0) emit(",");
			expr1.accept(this);
		}
		emit("]");
    return null;
	}
	String visit(BinaryExpr expr) {
    expr.left.accept(this);
    emit(expr.operator.value);
    expr.right.accept(this);
    return null;
  }
  String visit(PipeExpr expr) {
    //auto a = delegate() { 1 + 2; };
    //a();

    // return "(delegate() { " ~ expr.right.accept(this) ~ " = " ~ expr.left.accept(this) ~ "; })()";
    refer = true;
    write = false;
    String target = expr.right.accept(this);
    generators = [];
    expr.left.accept(this);
    write = true;
    refer = false;




    emit(target);
    emit(".__add((ulong __idx) { ");

    foreach(gen; generators) {
      //if (auto declExpr = cast(DeclExpr)gen) {
      emit(gen);
      emit(".__tick(__idx); ");
      //}
    }
    emit(" ");
    expr.right.accept(this);
    emit(" = ");
    expr.left.accept(this);
    emit(";})");

    //auto s =  ~ ticks ~ " " ~ target2 ~ " = " ~ e ~";})";// writefln(\"%s\", " ~ e ~ ");})";
    return null;
		//return "pipe(" ~ expr.left.accept(this) ~ "," ~ expr.right.accept(this) ~ ")";
	}
	String visit(AssignExpr expr) {
    expr.left.accept(this);
    emit(expr.operator.value);
    expr.right.accept(this);
    return null;
		//return "assign!\""~expr.operator.value~"\"(" ~ expr.left.accept(this) ~ "," ~  expr.right.accept(this) ~ ")";
	}
	String visit(UnaryExpr expr) {
		emit("(");
    emit(expr.operator.value);
    expr.operand.accept(this);
    emit(")");
    return null;
	}
	String visit(CallExpr expr) {
    expr.expr.accept(this);
    emit("(");
		//if (expr.arguments.length == 1)
		//	s = "call!" ~ s;
		foreach (i, arg ; expr.arguments) {
			if (i != 0) emit(",");
			arg.accept(this);
		}
    emit(")");
		return null;
	}
	String visit(DeclStmt stmt) {
    //import duck.compiler.visitors;
    //writefln("DeclStmt %s %s", stmt.decl, stmt.decl.accept(ExprPrint()));
    switch (stmt.decl.declType.kind) {
      case StructType.Kind:
        emit((cast(StructType)stmt.decl.declType).name);
        emit(" ");
        emit(stmt.identifier.value);
        emit(";\n");
        return null;
      case GeneratorType.Kind:
        emit((cast(GeneratorType)stmt.decl.declType).name);
        emit(" ");
        emit(stmt.identifier.value);
        emit(" = ");
        stmt.expr.accept(this);;
        emit(";\n");
        return null;
        //return (cast(GeneratorType)stmt.decl.declType).name ~ " " ~ stmt.identifier.value ~ " = " ~ stmt.expr.accept(this) ~ ";\n";
      default:
        emit("ERRR");
        return null;
    }
	}
	String visit(ExprStmt stmt) {
		stmt.expr.accept(this);
    emit(";\n");
    return null;
	}
	String visit(Stmts expr) {
		foreach (i, stmt; expr.stmts) {
			stmt.accept(this);
		}
		return null;
	}
  String visit(DeclExpr expr) {
    emit(expr.identifier.value);
    return null;
    //return expr.identifier.value;
    //import duck.compiler.visitors;
    //writefln("%s %s", expr.decl, expr.decl.accept(ExprPrint()));
    //return expr.decl.accept(this);
  }
	String visit(ScopeStmt expr) {
    emit("{");
		expr.stmts.accept(this);
    emit("}\n");
    return null;
	}
	String visit(Program mod) {
		foreach (i, node; mod.nodes) {
			node.accept(this);
		}
		return output.data;
	}
};
