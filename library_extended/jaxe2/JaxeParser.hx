package jaxe;

import jaxe.JaxeExpr;
import Std;

class JaxeParser {
	public var lastLine:Int = 1;
	public var lastCol:Int = 1;

	var pos:Int = 0;
	var code:String;

	public function new() {}

	public function parseString(source:String, scriptName:String):Array<JaxeExpr> {
		this.code = source;
		this.pos = 0;
		this.lastLine = 1;
		this.lastCol = 1;

		var ast = new Array<JaxeExpr>();
		while (pos < code.length) {
			skipWhitespace();
			if (pos >= code.length) break;

			var oldPos = pos;
			var statement = parseFullExpr();
			if (statement != null) ast.push(statement);

			if (pos == oldPos) {
				JaxeScript.handleError('Unexpected token \'${peek()}\'', lastLine, lastCol, null, scriptName);
				break;
			}
		}
		return ast;
	}

	inline function skipWhitespace() {
		while (pos < code.length) {
			var c = code.charCodeAt(pos);
			if (c == 10) { lastLine++; lastCol = 1; pos++; }
			else if (c == 32 || c == 9 || c == 13) { lastCol++; pos++; }
			else if (c == 47 && code.charCodeAt(pos + 1) == 47) {
				while (pos < code.length && code.charCodeAt(pos) != 10) pos++;
			}
			else if (c == 47 && code.charCodeAt(pos + 1) == 42) {
				pos += 2; lastCol += 2;
				while (pos < code.length) {
					if (code.charCodeAt(pos) == 42 && code.charCodeAt(pos+1) == 47) { pos += 2; lastCol += 2; break; }
					if (code.charCodeAt(pos) == 10) { lastLine++; lastCol = 1; } else { lastCol++; }
					pos++;
				}
			}
			else break;
		}
	}

	inline function peekAt(offset:Int):String { return offset < code.length ? code.charAt(offset) : ""; }
	inline function peek():String { return pos < code.length ? code.charAt(pos) : ""; }

	function consume(s:String) {
		skipWhitespace();
		if (code.substr(pos, s.length) == s) { pos += s.length; lastCol += s.length; }
		else JaxeScript.handleError('Expected \'$s\' Found: \'${peek()}\'', lastLine, lastCol, null, "Parser");
	}
	inline function isDigit(c:Int):Bool { return c >= 48 && c <= 57; }

	function peekIdent():String {
		var oldPos = pos; var oldCol = lastCol;
		var id = readIdent();
		pos = oldPos; lastCol = oldCol;
		return id;
	}

	function readIdent(peekMode:Bool = false):String {
		var oldPos = pos; var oldCol = lastCol; skipWhitespace();
		var start = pos;
		while (pos < code.length) {
			var c = code.charCodeAt(pos);
			if (pos == start) {
				if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95) { pos++; lastCol++; } else break;
			} else {
				if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || (c >= 48 && c <= 57)) { pos++; lastCol++; } else break;
			}
		}
		var res = code.substring(start, pos);
		if (peekMode) { pos = oldPos; lastCol = oldCol; }
		return res;
	}

	function readTypePath():String {
		skipWhitespace();
		var start = pos;
		while (pos < code.length) {
			var c = code.charCodeAt(pos);
			if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || (c >= 48 && c <= 57) || c == 46) { pos++; lastCol++; }
			else break;
		}
		return code.substring(start, pos);
	}

	function checkArrayType(baseType:String):String {
		var oldP = pos; var oldC = lastCol;
		if (peek() == "[") {
			pos++; lastCol++; skipWhitespace();
			if (peek() == "]") {
				pos++; lastCol++; skipWhitespace();
				return baseType + "[]";
			}
		}
		pos = oldP; lastCol = oldC;
		return baseType;
	}

	function parseFullExpr():JaxeExpr {
		skipWhitespace();

		if (peek() == "{") {
			consume("{"); var exprs = [];
			while (peek() != "}") { exprs.push(parseFullExpr()); skipWhitespace(); }
			consume("}"); return EBlock(exprs);
		}

		var localPos = pos; var localCol = lastCol;
		var mod = readIdent();
		while (mod == "private" || mod == "public" || mod == "static" || mod == "override" || mod == "final") {
			mod = readIdent(); skipWhitespace();
		}

		var typeStr = mod;
		typeStr = checkArrayType(typeStr);
		var funcName = readIdent();

		if (peek() == "(" && typeStr != "" && funcName != "" && typeStr != "if" && typeStr != "while" && typeStr != "for" && typeStr != "switch" && typeStr != "new" && typeStr != "catch" && typeStr != "return") {
			consume("("); var args = [];
			while (peek() != ")") {
				skipWhitespace(); var argName = ""; var argType = "Dynamic";

				var t1 = readTypePath(); skipWhitespace();
				t1 = checkArrayType(t1);

				if (peek() == ":") {
					consume(":"); skipWhitespace();
					var t2 = readTypePath(); skipWhitespace();
					t2 = checkArrayType(t2);
					argName = t1; argType = t2;
				} else {
					var t2 = t1;
					var n2 = readIdent(); skipWhitespace();
					if (n2 == "") { argName = t2; argType = "Dynamic"; }
					else { argType = t2; argName = n2; }
				}

				args.push({name: argName, type: argType}); skipWhitespace();
				if (peek() == ",") consume(",");
			}
			consume(")");
			return EVarDecl(funcName, "Dynamic", EFunction(args, parseFullExpr()), false, false);
		}
		pos = localPos; lastCol = localCol;

		var oldPos = pos; var oldCol = lastCol;
		var id = readIdent();

		if (id == "if") {
			consume("("); var cond = parseExpr(); consume(")");
			var e1 = parseFullExpr(); var e2 = null;
			skipWhitespace();
			if (peekIdent() == "else") { readIdent(); e2 = parseFullExpr(); }
			return EIf(cond, e1, e2);
		} else if (id == "while") {
			consume("("); var cond = parseExpr(); consume(")");
			return EWhile(cond, parseFullExpr());
		} else if (id == "for") {
			consume("(");
			var isForEach = false; var tempPos = pos;
			while(tempPos < code.length && peekAt(tempPos) != ")") {
				if (peekAt(tempPos) == ":") { isForEach = true; break; }
				if (peekAt(tempPos) == ";") { isForEach = false; break; }
				tempPos++;
			}

			if (isForEach) {
				var itypeStr = readTypePath(); skipWhitespace();
				itypeStr = checkArrayType(itypeStr);
				var varName = itypeStr;
				if (peek() != ":") varName = readIdent();
				consume(":"); var iterable = parseExpr(); consume(")");
				return EForEach(varName, iterable, parseFullExpr());
			} else {
				var initExpr = null;
				if (peek() != ";") {
					var t1 = readTypePath(); skipWhitespace();
					t1 = checkArrayType(t1);
					var t2 = readIdent(true);
					if (t2 != "" && t2 != "=") {
						var varName = readIdent(); consume("="); initExpr = EVarDecl(varName, t1, parseExpr(), false, false);
					} else { pos -= t1.length; initExpr = parseExpr(); }
				}
				consume(";"); var condExpr = (peek() != ";") ? parseExpr() : null;
				consume(";"); var incExpr = (peek() != ")") ? parseExpr() : null; consume(")");
				return EFor(initExpr, condExpr, incExpr, parseFullExpr());
			}
		} else if (id == "switch") {
			consume("("); var cond = parseExpr(); consume(")"); consume("{");
			var cases = []; var defaultBody = null;
			while (peek() != "}") {
				skipWhitespace(); var keyword = readIdent();
				if (keyword == "case") {
					var cVal = parseExpr(); consume(":"); var cBody = [];
					while (peek() != "}" && peekIdent() != "case" && peekIdent() != "default") { cBody.push(parseFullExpr()); skipWhitespace(); }
					cases.push({val: cVal, body: cBody});
				} else if (keyword == "default") {
					consume(":"); defaultBody = [];
					while (peek() != "}" && peekIdent() != "case") { defaultBody.push(parseFullExpr()); skipWhitespace(); }
				}
			}
			consume("}"); return ESwitch(cond, cases, defaultBody);
		} else if (id == "try") {
			var tryBlock = parseFullExpr(); skipWhitespace();
			if (readIdent() != "catch") {
				JaxeScript.handleError("Expected 'catch' after 'try'", lastLine, lastCol, null, "Parser");
				return null;
			}
			consume("("); readTypePath(); var catchVar = readIdent(); consume(")");
			return ETry(tryBlock, catchVar, parseFullExpr());
		} else if (id == "break") { consume(";"); return EBreak;
		} else if (id == "continue") { consume(";"); return EContinue;

		// Return Node parsing
		} else if (id == "return") {
			var retExpr = null;
			skipWhitespace();
			if (peek() != ";") retExpr = parseExpr();
			if (peek() == ";") consume(";");
			return EReturn(retExpr);

		} else if (id == "package") {
			var pack = readIdent(); while (peek() == ".") { consume("."); pack += "." + readIdent(); }
			consume(";"); return EPackage(pack);
		} else if (id == "import" || id == "using") {
			skipWhitespace(); var startPos = pos; var isExpr = false;
			if (peek() == "\"") isExpr = true;
			else {
				var tempPos = pos;
				while (tempPos < code.length && code.charAt(tempPos) != ";") {
					var c = code.charAt(tempPos);
					if (c == "(" || c == "+" || c == "\"" || c == "'") { isExpr = true; break; }
					tempPos++;
				}
			}
			if (isExpr) {
				pos = startPos; var expr = parseExpr(); if (peek() == ";") consume(";");
				return id == "import" ? EScriptImport(expr) : EScriptUsing(expr);
			}
			else {
				pos = startPos; var pack = readIdent(); while (peek() == ".") { consume("."); pack += "." + readIdent(); }
				if (peek() == ";") consume(";");
				return id == "import" ? EImport(pack) : EUsing(pack);
			}
		} else if (id == "enum") {
			var enumName = readIdent();
			if (enumName == "") enumName = "AnonEnum_" + pos;
			consume("{"); var fields = [];
			while(peek() != "}") {
				skipWhitespace(); var fieldName = readIdent();
				if (fieldName != "") fields.push(fieldName); else if (peek() != "}" && peek() != ",") { pos++; lastCol++; }
				skipWhitespace(); if (peek() == ",") consume(",");
			}
			consume("}"); return EEnum(enumName, fields);
		} else if (id == "class" || id == "interface") {
			var className = readIdent(); var superclass = ""; var interfaces = []; var typeParams = [];
			skipWhitespace();
			if (peek() == "<") {
				consume("<"); while(peek() != ">") { skipWhitespace(); typeParams.push(readIdent()); skipWhitespace(); if(peek()==",") consume(","); } consume(">");
			}
			skipWhitespace();
			if (readIdent(true) == "extends") { readIdent(); superclass = readIdent(); }
			skipWhitespace();
			if (readIdent(true) == "implements") {
				readIdent(); while(peek() != "{") { skipWhitespace(); interfaces.push(readIdent()); skipWhitespace(); if(peek()==",") consume(","); }
			}
			consume("{"); var members = [];
			while (peek() != "}") { skipWhitespace(); if (peek() == "}") break; members.push(parseMember()); }
			consume("}"); return EClass(className, superclass, interfaces, typeParams, members);
		}

		pos = oldPos; lastCol = oldCol;

		var vTypeStr = readTypePath(); skipWhitespace();
		vTypeStr = checkArrayType(vTypeStr);
		var vVarName = readIdent(); skipWhitespace();

		if (vTypeStr != "" && vVarName != "" && vTypeStr != "return" && vTypeStr != "new" && (peek() == "=" || peek() == ";")) {
			if (peek() == "=") { consume("="); var init = parseExpr(); if (peek() == ";") consume(";"); return EVarDecl(vVarName, vTypeStr, init, false, false); }
			else { if (peek() == ";") consume(";"); return EVarDecl(vVarName, vTypeStr, null, false, false); }
		}

		pos = oldPos; lastCol = oldCol;
		var expr = parseExpr();
		if (peek() == ";") consume(";");
		return expr;
	}

	function parseMember():JaxeExpr {
		var oldPos = pos; var oldCol = lastCol; skipWhitespace();
		var isOverride = false;
		if (peek() == "@") { consume("@"); if (readIdent() == "Override") isOverride = true; skipWhitespace(); }

		var isPriv = false; var isStatic = false;
		var mod = readIdent();

		if (mod == "enum") {
			var enumName = readIdent();
			if (enumName == "") enumName = "AnonEnum_" + pos;
			consume("{"); var fields = [];
			while(peek() != "}") {
				skipWhitespace(); var fieldName = readIdent();
				if (fieldName != "") fields.push(fieldName); else if (peek() != "}" && peek() != ",") { pos++; lastCol++; }
				skipWhitespace(); if (peek() == ",") consume(",");
			}
			consume("}"); return EEnum(enumName, fields);
		}

		pos = oldPos; lastCol = oldCol; skipWhitespace();
		if (peek() == "@") { consume("@"); readIdent(); skipWhitespace(); }

		while (true) {
			mod = readIdent();
			if (mod == "private") isPriv = true; else if (mod == "public") {} else if (mod == "static") isStatic = true; else { pos -= mod.length; break; }
			skipWhitespace();
		}

		var type = readTypePath(); skipWhitespace();
		type = checkArrayType(type);
		var name = readIdent(); skipWhitespace();

		if (peek() == "(") {
			consume("("); var args = [];
			while (peek() != ")") {
				skipWhitespace(); var argName = ""; var argType = "Dynamic";
				var t1 = readTypePath(); skipWhitespace();
				t1 = checkArrayType(t1);

				if (peek() == ":") {
					consume(":"); skipWhitespace();
					var t2 = readTypePath(); skipWhitespace();
					t2 = checkArrayType(t2);
					argName = t1; argType = t2;
				} else {
					var t2 = t1;
					var n2 = readIdent(); skipWhitespace();
					if (n2 == "") { argName = t2; argType = "Dynamic"; } else { argType = t2; argName = n2; }
				}

				args.push({name: argName, type: argType}); skipWhitespace();
				if (peek() == ",") consume(",");
			}
			consume(")"); return EMethod(name, type, args, parseFullExpr(), isOverride, isStatic);
		} else if (peek() == "=") {
			consume("="); var init = parseExpr(); if (peek() == ";") consume(";"); return EVarDecl(name, type, init, isPriv, isStatic);
		} else {
			if (peek() == ";") consume(";"); return EVarDecl(name, type, null, isPriv, isStatic);
		}
	}

	function parseExpr():JaxeExpr {
		skipWhitespace();
		var unop = ""; if (peek() == "!") { consume("!"); unop = "!"; skipWhitespace(); }

		var id = readIdent(); var left:JaxeExpr = null;

		if (id == "this") left = EThis;
		else if (id == "super") left = ESuper;
		else if (id == "true") left = EBool(true);
		else if (id == "false") left = EBool(false);
		else if (id == "new") {
			skipWhitespace(); var cls = readTypePath(); skipWhitespace();
			var tParams = [];
			if (peek() == "<") { consume("<"); skipWhitespace(); while(peek() != ">") { tParams.push(readTypePath()); skipWhitespace(); if(peek()==",") { consume(","); skipWhitespace(); } } consume(">"); skipWhitespace(); }

			if (peek() == "[") {
				consume("["); skipWhitespace();
				var sizeExpr = null;
				if (peek() != "]") { sizeExpr = parseExpr(); skipWhitespace(); }
				consume("]"); skipWhitespace();

				if (peek() == "{") {
					consume("{"); skipWhitespace();
					var items = [];
					while (peek() != "}") {
						items.push(parseExpr()); skipWhitespace();
						if (peek() == ",") { consume(","); skipWhitespace(); if (peek() == "}") break; }
					}
					consume("}"); left = EArrayDecl(items);
				} else if (sizeExpr != null) {
					left = ENewArray(cls, sizeExpr);
				} else left = EArrayDecl([]);
			}
			else {
				consume("("); skipWhitespace();
				var args = [];
				while(peek() != ")") {
					args.push(parseExpr()); skipWhitespace();
					if(peek()==",") { consume(","); skipWhitespace(); if (peek() == ")") break; }
				}
				consume(")"); left = ENew(cls, tParams, args);
			}
		}
		else if (id != "") left = EIdent(id);
		else if (peek() == "\"") {
			consume("\""); var start = pos;
			while (peek() != "\"") { pos++; lastCol++; }
			var str = code.substring(start, pos); consume("\""); left = EString(str, false);
		}
		else if (peek() == "'") {
			consume("'"); var start = pos;
			while (peek() != "'") { pos++; lastCol++; }
			var str = code.substring(start, pos); consume("'"); left = EString(str, true);
		}
		else if (peek() == "[" || peek() == "{") {
			var isBrace = peek() == "{"; consume(isBrace ? "{" : "["); skipWhitespace();
			var items = [];
			while (peek() != (isBrace ? "}" : "]")) {
				items.push(parseExpr()); skipWhitespace();
				if (peek() == ",") { consume(","); skipWhitespace(); if (peek() == (isBrace ? "}" : "]")) break; }
			}
			consume(isBrace ? "}" : "]"); left = EArrayDecl(items);
		} else {
			var numStart = pos; if (peek() == "-") { pos++; lastCol++; }
			while (pos < code.length && (isDigit(code.charCodeAt(pos)) || peek() == ".")) { pos++; lastCol++; }
			var numStr = code.substring(numStart, pos);
			if (numStr != "" && numStr != "-") { left = numStr.indexOf(".") != -1 ? EFloat(Std.parseFloat(numStr)) : EInt(Std.parseInt(numStr)); }
			else {
				JaxeScript.handleError('Unexpected token \'${peek()}\'', lastLine, lastCol, null, "Parser");
				return null;
			}
		}

		if (unop != "") left = EUnop(unop, left);

		skipWhitespace();
		while (pos < code.length) {
			if (peek() == ".") { consume("."); skipWhitespace(); left = EField(left, readIdent()); }
			else if (peek() == "(") {
				consume("("); skipWhitespace();
				var args = [];
				while (peek() != ")") {
					args.push(parseExpr()); skipWhitespace();
					if (peek() == ",") { consume(","); skipWhitespace(); if (peek() == ")") break; }
				}
				consume(")"); left = ECall(left, args);
			}
			else if (peek() == "[") { consume("["); skipWhitespace(); var idx = parseExpr(); skipWhitespace(); consume("]"); left = EArrayAccess(left, idx); }
			else break;
			skipWhitespace();
		}

		skipWhitespace();
		if (peek() == "+" && peekAt(pos+1) == "+") { consume("++"); left = EPostfix(left, "++"); }
		if (peek() == "-" && peekAt(pos+1) == "-") { consume("--"); left = EPostfix(left, "--"); }

		while (pos < code.length) {
			skipWhitespace(); var p = peek();

			if (p == "=" && peekAt(pos+1) == ">") {
				consume("=>"); left = EBinop("=>", left, parseExpr()); continue;
			}

			if (p == "+" || p == "-" || p == "*" || p == "/" || p == "%" || p == "<" || p == ">" || p == "=" || p == "!" || p == "&" || p == "|") {
				var op = p; consume(p);
				if (peek() == "=" && (p == "+" || p == "-" || p == "*" || p == "/" || p == "%")) { consume("="); left = EAssign(left, EBinop(p, left, parseExpr())); continue; }
				if (peek() == "=" && (p == "<" || p == ">" || p == "!" || p == "=")) { op += "="; consume("="); }
				else if (p == "&" && peek() == "&") { op = "&&"; consume("&"); } else if (p == "|" && peek() == "|") { op = "||"; consume("|"); }

				if (op == "=") left = EAssign(left, parseExpr()); else left = EBinop(op, left, parseExpr());
			} else break;
		}

		return left;
	}
}
