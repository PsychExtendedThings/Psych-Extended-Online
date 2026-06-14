package jaxe;

import jaxe.JaxeExpr;
import Reflect;
import Type;
import Std;
import haxe.Constraints.IMap;

class JaxeInterp {
	public var scriptObject:Dynamic;
	public var extendedObject:Dynamic;
	public var scriptName:String = "Unknown";

	public var locals:Map<String, {args:Array<{name:String, type:String}>, body:JaxeExpr}> = new Map();
	public var variables:Map<String, Dynamic> = new Map();
	public var superMethods:Map<String, Dynamic> = new Map();
	public var scriptClasses:Map<String, Dynamic> = new Map();

	public static var instanceVars:haxe.ds.ObjectMap<Dynamic, Map<String, Dynamic>> = new haxe.ds.ObjectMap();

	var imports:Map<String, Dynamic> = new Map();
	var usings:Array<Dynamic> = [];

	public function new() {
		try { usings.push(Type.resolveClass("StringTools")); } catch(e:Dynamic) {}
		try { usings.push(Type.resolveClass("Std")); } catch(e:Dynamic) {}
		try { usings.push(Type.resolveClass("Math")); } catch(e:Dynamic) {}

		var systemOut = {
			println: Reflect.makeVarArgs(function(args) { printMsg(args.join("")); return null; }),
			print: Reflect.makeVarArgs(function(args) {
				var msg = args.join(""); #if sys Sys.print(msg); #else trace(msg); #end
				return null;
			})
		};
		variables.set("System", { out: systemOut });
	}

	public function printMsg(msg:String) {
		var prefix = "";
		switch (JaxeConfig.PRINT_PREFIX) {
			case SOURCE: prefix = scriptName + ": ";
			case SCRIPT: prefix = "[Jaxe Script]: ";
			case CUSTOM(p): prefix = p;
		}
		#if sys Sys.println(prefix + msg); #else trace(prefix + msg); #end
	}

	public function setVar(name:String, value:Dynamic) variables.set(name, value);

	public function call(name:String, args:Array<Dynamic>):Dynamic {
		if (!locals.exists(name)) {
			JaxeScript.handleError('Method \'$name\' not found in script locals.', 0, 0, null, scriptName, true);
			return null;
		}
		var m = locals.get(name);

		var oldVars = new Map<String, Dynamic>();
		for (i in 0...m.args.length) {
			var argName = m.args[i].name;
			if (variables.exists(argName)) oldVars.set(argName, variables.get(argName));
			variables.set(argName, i < args.length ? args[i] : null);
		}

		var res = null;
		try { res = expr(m.body); }
		catch(e:Dynamic) {
			if (Std.isOfType(e, Array) && e[0] == "JAXE_RETURN") res = e[1];
			else if (e != "JAXE_BREAK" && e != "JAXE_CONTINUE") JaxeScript.handleError("Jaxe Runtime Error in [" + name + "]", 0, 0, e, scriptName, false);
		}

		for (i in 0...m.args.length) {
			var argName = m.args[i].name;
			if (oldVars.exists(argName)) variables.set(argName, oldVars.get(argName));
			else variables.remove(argName);
		}
		return res;
	}

	public function execute(ast:Array<JaxeExpr>) {
		for (e in ast) {
			switch(e) {
				case EClass(name, superclass, interfaces, typeParams, members):
					scriptClasses.set(name, { data: { superclass: superclass, members: members }, interp: this });
				default:
			}
		}
		for (e in ast) expr(e);
	}

	public function instantiateClass(cls:String, args:Array<Dynamic>):Dynamic {
		var sInterp = scriptClasses.get(cls).interp;
		var hierarchy = new Array<String>();
		var currCls = cls;
		while (currCls != "" && sInterp.scriptClasses.exists(currCls)) {
			hierarchy.unshift(currCls);
			currCls = sInterp.scriptClasses.get(currCls).data.superclass;
		}

		var localObj:Dynamic = null;
		if (currCls != "") {
			var sCls = Type.resolveClass(currCls);
			if (sCls == null && sInterp.imports.exists(currCls)) sCls = sInterp.imports.get(currCls);
			if (sCls != null) localObj = Type.createInstance(sCls, []); // State creation
		}
		if (localObj == null) localObj = {};

		try { Reflect.setProperty(localObj, "scriptInterp", sInterp); } catch(err:Dynamic) {}
		sInterp.extendedObject = localObj;

		var instVars = new Map<String, Dynamic>();
		JaxeInterp.instanceVars.set(localObj, instVars);

		for (hierarchyClass in hierarchy) {
			var sClass = sInterp.scriptClasses.get(hierarchyClass).data;
			for(m in (sClass.members : Array<JaxeExpr>)) {
				switch(m) {
					case EVarDecl(vName, _, init, _, isStatic):
						if (!isStatic) {
							var prevCtx = sInterp.extendedObject;
							sInterp.extendedObject = localObj;
							var val = init != null ? sInterp.expr(init) : null;
							sInterp.extendedObject = prevCtx;

							instVars.set(vName, val);
							try { Reflect.setProperty(localObj, vName, val); } catch(err:Dynamic) {}
						}
					case EEnum(eName, eFields): sInterp.expr(m);
					case EMethod(mName, mType, mArgs, mBody, mIsOverride, mIsStatic):
						if (!mIsStatic) {
							sInterp.expr(m);
							var methodClosure = Reflect.makeVarArgs(function(funcArgs) {
								var prevObj = sInterp.extendedObject;
								sInterp.extendedObject = localObj;
								var res = sInterp.call(mName, funcArgs);
								sInterp.extendedObject = prevObj;
								return res;
							});
							instVars.set(mName, methodClosure);
							try { Reflect.setProperty(localObj, mName, methodClosure); } catch(err:Dynamic) {}
						}
					default:
				}
			}
		}

		var prevObj = sInterp.extendedObject;
		sInterp.extendedObject = localObj;

		if (sInterp.locals.exists(cls)) sInterp.call(cls, args);
		else if (sInterp.locals.exists("new")) sInterp.call("new", args);

		sInterp.extendedObject = prevObj;
		return localObj;
	}

	public function expr(e:JaxeExpr):Dynamic {
		if (e == null) return null;
		switch (e) {
			case EPackage(pack): return null;
			case EImport(pack):
				if (pack == "java.util.Arrays") {
					imports.set("Arrays", {
						toString: function(arr:Dynamic) {
							if (arr == null) return "null";
							if (Std.isOfType(arr, Array)) return "[" + cast(arr, Array<Dynamic>).join(", ") + "]";
							return Std.string(arr);
						}
					});
					return null;
				}

				var parts = pack.split(".");
				var clsName = parts[parts.length - 1];
				if (!imports.exists(clsName)) {
					var cls = Type.resolveClass(pack);
					if (cls == null) cls = Type.resolveClass(clsName);

					if (cls == null) JaxeScript.handleError('Class \'$pack\' not found in import.', 0, 0, null, scriptName, true);
					else imports.set(clsName, cls);
				}
				return null;

			case EEnum(name, fields):
				var enumObj:Dynamic = {};
				for(i in 0...fields.length) {
					Reflect.setProperty(enumObj, fields[i], i);
					if (StringTools.startsWith(name, "AnonEnum_")) variables.set(fields[i], i);
				}
				if (!StringTools.startsWith(name, "AnonEnum_")) variables.set(name, enumObj);
				return null;

			case EScriptImport(pathExpr):
				var path:String = expr(pathExpr);
				#if sys
				if (sys.FileSystem.exists(path)) {
					var subParser = new JaxeParser();
					var subAst = subParser.parseString(sys.io.File.getContent(path), path);
					var subInterp = new JaxeInterp(); subInterp.scriptName = path;

					for (astExpr in subAst) {
						switch(astExpr) {
							case EClass(_,_,_,_,_), EEnum(_,_), EImport(_), EScriptImport(_), EUsing(_), EScriptUsing(_): subInterp.expr(astExpr);
							default:
						}
					}
					for (k in subInterp.scriptClasses.keys()) {
						scriptClasses.set(k, { data: subInterp.scriptClasses.get(k).data, interp: subInterp });
						if (subInterp.variables.exists(k)) variables.set(k, subInterp.variables.get(k));
					}
				} else JaxeScript.handleError('Import Error: Script not found at $path', 0, 0, null, scriptName, false);
				#end
				return null;

			case EUsing(pack):
				var cls = Type.resolveClass(pack);
				if (cls == null) { var parts = pack.split("."); cls = Type.resolveClass(parts[parts.length - 1]); }
				if (cls != null) usings.push(cls);
				else JaxeScript.handleError('Using Warning: Class \'$pack\' not found.', 0, 0, null, scriptName, true);
				return null;

			case EScriptUsing(pathExpr):
				var path:String = expr(pathExpr);
				#if sys
				if (sys.FileSystem.exists(path)) {
					var subParser = new JaxeParser(); var subAst = subParser.parseString(sys.io.File.getContent(path), path); this.execute(subAst);
					for (astExpr in subAst) { switch(astExpr) { case EClass(name, _, _, _, _): if (variables.exists(name)) usings.push(variables.get(name)); default: } }
				} else JaxeScript.handleError('Using Warning: Script not found at $path', 0, 0, null, scriptName, true);
				#end
				return null;

			case EClass(name, superclass, interfaces, typeParams, members):
				if (superclass != "") {
					if (JaxeConfig.DISALLOW_OVERRIDE_CLASSES.indexOf(superclass) != -1) {
						JaxeScript.handleError('Class Extension Error: Extending \'$superclass\' is disallowed by JaxeConfig.', 0, 0, null, scriptName, false);
						return null;
					}

					if (!scriptClasses.exists(superclass)) {
						var cls = Type.resolveClass(superclass);
						if (cls == null && imports.exists(superclass)) cls = imports.get(superclass);

						if (cls != null) {
							extendedObject = Type.createInstance(cls, []);
							try { Reflect.setProperty(extendedObject, "scriptInterp", this); } catch(err:Dynamic) {}
						} else JaxeScript.handleError('Class Extension Warning: Superclass \'$superclass\' not found.', 0, 0, null, scriptName, true);
					}
				}

				var classObj:Dynamic = {}; variables.set(name, classObj);
				scriptClasses.set(name, { data: { superclass: superclass, members: members }, interp: this });

				for (m in members) {
					switch (m) {
						case EMethod(mName, _, _, _, _, isStatic): if (isStatic) Reflect.setProperty(classObj, mName, Reflect.makeVarArgs(function(args) return call(mName, args)));
						case EVarDecl(vName, _, init, _, isStatic): if (isStatic) Reflect.setProperty(classObj, vName, init != null ? expr(init) : null);
						default:
					}
					if (m.match(EVarDecl(_,_,_,_,false))) continue;
					expr(m);
				}
				return null;

			case EVarDecl(name, type, init, isPriv, isStatic): variables.set(name, init != null ? expr(init) : null); return null;

			case EFunction(args, body):
				return Reflect.makeVarArgs(function(funcArgs:Array<Dynamic>) {
					var oldVars = new Map<String, Dynamic>();
					for (i in 0...args.length) { var argName = args[i].name; if (variables.exists(argName)) oldVars.set(argName, variables.get(argName)); variables.set(argName, i < funcArgs.length ? funcArgs[i] : null); }
					var res = null;
					try { res = expr(body); }
					catch(e:Dynamic) { if (Std.isOfType(e, Array) && e[0] == "JAXE_RETURN") res = e[1]; else if (e != "JAXE_BREAK" && e != "JAXE_CONTINUE") throw e; }
					for (i in 0...args.length) { var argName = args[i].name; if (oldVars.exists(argName)) variables.set(argName, oldVars.get(argName)); else variables.remove(argName); }
					return res;
				});

			case EMethod(name, type, args, body, isOverride, isStatic):
				var targetObj = extendedObject; var hasSuper = false; var originalMethod:Dynamic = null;
				var cleanName = StringTools.startsWith(name, "scripted_") ? name.substring(9) : name;
				var hookName = cleanName;

				if (targetObj != null && !isStatic) {
					if (Reflect.hasField(targetObj, "scripted_" + cleanName) || Reflect.getProperty(targetObj, "scripted_" + cleanName) != null) {
						hasSuper = true; hookName = "scripted_" + cleanName; originalMethod = Reflect.getProperty(targetObj, hookName);
					} else if (Reflect.hasField(targetObj, cleanName) || Reflect.getProperty(targetObj, cleanName) != null) {
						hasSuper = true; originalMethod = Reflect.getProperty(targetObj, cleanName);
					}
				}

				locals.set(cleanName, {args: args, body: body});

				if (hasSuper) {
					if (originalMethod != null) superMethods.set(cleanName, originalMethod);
					var scriptFunc = Reflect.makeVarArgs(function(funcArgs) return call(cleanName, funcArgs));
					try { Reflect.setProperty(targetObj, hookName, scriptFunc); } catch(err:Dynamic) {}
				}
				return null;

			case ENew(cls, typeParams, args):
				if (scriptClasses.exists(cls)) return instantiateClass(cls, args.map(expr));

				var tCls = Type.resolveClass(cls);
				if (tCls == null && imports.exists(cls)) tCls = imports.get(cls);
				if (tCls == null) {
					if (variables.exists(cls) || cls == scriptName.split(".")[0]) { if (extendedObject != null) return extendedObject; }
					JaxeScript.handleError('Instantiation Warning: Class \'$cls\' not found.', 0, 0, null, scriptName, true);
					return null;
				}
				return Type.createInstance(tCls, args.map(expr));

			case ENewArray(cls, size): var s:Int = Std.int(cast expr(size)); var arr = new Array<Dynamic>(); for(i in 0...s) arr.push(null); return arr;

			case EPostfix(astExpr, op):
				var orig:Float = expr(astExpr); var newVal = (op == "++") ? orig + 1 : orig - 1;
				switch(astExpr) {
					case EIdent(id):
						if (variables.exists(id)) variables.set(id, newVal);
						else if (extendedObject != null) {
							var instVars = JaxeInterp.instanceVars.get(extendedObject);
							if (instVars != null && instVars.exists(id)) { instVars.set(id, newVal); try { Reflect.setProperty(extendedObject, id, newVal); } catch(err:Dynamic) {} }
							else if (Reflect.hasField(extendedObject, id) || Reflect.getProperty(extendedObject, id) != null) Reflect.setProperty(extendedObject, id, newVal);
							else variables.set(id, newVal);
						} else variables.set(id, newVal);

					case EArrayAccess(arrTarget, idxTarget):
						var arr:Dynamic = expr(arrTarget);
						if (arr != null) { var idx:Dynamic = expr(idxTarget); if (Std.isOfType(arr, IMap)) cast(arr, IMap<Dynamic, Dynamic>).set(idx, newVal); else arr[idx] = newVal; }

					case EField(objExpr, f):
						var obj = expr(objExpr); var assigned = false; var instVars = JaxeInterp.instanceVars.get(obj);
						if (instVars != null && instVars.exists(f)) { instVars.set(f, newVal); assigned = true; }
						try { Reflect.setProperty(obj, f, newVal); assigned = true; } catch(err:Dynamic) {}
						if (!assigned && instVars != null) instVars.set(f, newVal);
					default:
				} return orig;

			case EIf(cond, e1, e2): if (expr(cond) == true) return expr(e1); else if (e2 != null) return expr(e2); return null;
			case EWhile(cond, body): while (expr(cond) == true) { try { expr(body); } catch (err:String) { if (err == "JAXE_BREAK") break; if (err == "JAXE_CONTINUE") continue; throw err; } } return null;
			case EFor(init, cond, inc, body):
				if (init != null) expr(init);
				while (cond == null || expr(cond) == true) { try { expr(body); } catch (err:String) { if (err == "JAXE_BREAK") break; if (err == "JAXE_CONTINUE") { if (inc != null) expr(inc); continue; } throw err; } if (inc != null) expr(inc); } return null;
			case EForEach(varName, iterable, body):
				var iter:Array<Dynamic> = cast expr(iterable);
				if (iter != null) { for (item in iter) { variables.set(varName, item); try { expr(body); } catch (err:String) { if (err == "JAXE_BREAK") break; if (err == "JAXE_CONTINUE") continue; throw err; } } } return null;
			case ESwitch(cond, cases, def):
				var cVal:Dynamic = expr(cond); var matched = false;
				for (c in cases) { if (expr(c.val) == cVal) { matched = true; try { for(b in c.body) expr(b); } catch (err:String) { if (err == "JAXE_BREAK") break; else throw err; } break; } }
				if (!matched && def != null) { try { for(b in def) expr(b); } catch (err:String) { if (err == "JAXE_BREAK") {} else throw err; } } return null;
			case ETry(tryBlock, catchVar, catchBlock): try { expr(tryBlock); } catch(err:Dynamic) { variables.set(catchVar, err); expr(catchBlock); } return null;

			case EBreak: throw "JAXE_BREAK";
			case EContinue: throw "JAXE_CONTINUE";
			case EReturn(retExpr): var val = (retExpr != null) ? expr(retExpr) : null; throw ["JAXE_RETURN", val];

			case EBlock(exprs): var res:Dynamic = null; for (ex in exprs) res = expr(ex); return res;

			case EArrayDecl(exprs):
				if (exprs.length > 0 && exprs[0].match(EBinop("=>", _, _))) {
					var isAllString = true, isAllInt = true; var keys = [], values = [];
					for (e2 in exprs) {
						switch (e2) {
							case EBinop("=>", eKey, eVal): var k:Dynamic = expr(eKey); var v:Dynamic = expr(eVal); if (!Std.isOfType(k, String)) isAllString = false; if (!Std.isOfType(k, Int)) isAllInt = false; keys.push(k); values.push(v);
							default: JaxeScript.handleError("'=>' expected for map elements inside dictionary arrays.", 0, 0, null, scriptName, true); return null;
						}
					}
					var map:Dynamic = null;
					if (isAllInt) map = new haxe.ds.IntMap<Dynamic>(); else if (isAllString) map = new haxe.ds.StringMap<Dynamic>(); else map = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
					var castedMap:IMap<Dynamic,Dynamic> = cast map; for (i in 0...keys.length) castedMap.set(keys[i], values[i]); return map;
				} else { var a = new Array<Dynamic>(); for (ex in exprs) a.push(expr(ex)); return a; }

			case EArrayAccess(target, index): var arr:Dynamic = expr(target); if (arr != null) { var idx:Dynamic = expr(index); if (Std.isOfType(arr, IMap)) return cast(arr, IMap<Dynamic, Dynamic>).get(idx); return arr[idx]; } return null;
			case EUnop(op, astExpr): if (op == "!") return !expr(astExpr); return null;

			case EAssign(target, val):
				var value = expr(val);
				switch (target) {
					case EIdent(id):
						if (variables.exists(id)) variables.set(id, value);
						else if (extendedObject != null) {
							var instVars = JaxeInterp.instanceVars.get(extendedObject);
							if (instVars != null && instVars.exists(id)) { instVars.set(id, value); try { Reflect.setProperty(extendedObject, id, value); } catch(err:Dynamic) {} }
							else if (Reflect.hasField(extendedObject, id) || Reflect.getProperty(extendedObject, id) != null) Reflect.setProperty(extendedObject, id, value);
							else variables.set(id, value);
						} else variables.set(id, value);

					case EArrayAccess(arrTarget, idxTarget):
						var arr:Dynamic = expr(arrTarget);
						if (arr != null) { var idx:Dynamic = expr(idxTarget); if (Std.isOfType(arr, IMap)) cast(arr, IMap<Dynamic, Dynamic>).set(idx, value); else arr[idx] = value; }

					case EField(objExpr, field):
						var obj = expr(objExpr);
						if (obj != null) {
							var assigned = false; var instVars = JaxeInterp.instanceVars.get(obj);
							if (instVars != null) { instVars.set(field, value); assigned = true; }
							try { Reflect.setProperty(obj, field, value); assigned = true; } catch(err:Dynamic) {}
							if (!assigned) { instVars = new Map<String, Dynamic>(); instVars.set(field, value); JaxeInterp.instanceVars.set(obj, instVars); }
						}
					default:
				} return value;

			case EField(target, field):
				if (target == ESuper) {
					if (superMethods.exists(field)) return superMethods.get(field);
					return Reflect.getProperty(extendedObject, field);
				}
				if (target == EThis) {
					if (extendedObject != null) {
						var instVars = JaxeInterp.instanceVars.get(extendedObject);
						if (instVars != null && instVars.exists(field)) return instVars.get(field);
						return Reflect.getProperty(extendedObject, field);
					}
					if (scriptObject != null && (Reflect.hasField(scriptObject, field) || Reflect.getProperty(scriptObject, field) != null)) return Reflect.getProperty(scriptObject, field);
					if (variables.exists(field)) return variables.get(field);
				}

				var tEval = expr(target);
				if (tEval == null) return null;

				var instVars = JaxeInterp.instanceVars.get(tEval);
				if (instVars != null && instVars.exists(field)) return instVars.get(field);
				return Reflect.getProperty(tEval, field);

			case EIdent(id):
				if (variables.exists(id)) return variables.get(id);
				if (locals.exists(id)) return Reflect.makeVarArgs(function(args) return call(id, args));
				if (extendedObject != null) {
					var instVars = JaxeInterp.instanceVars.get(extendedObject);
					if (instVars != null && instVars.exists(id)) return instVars.get(id);
					if (Reflect.hasField(extendedObject, id) || Reflect.getProperty(extendedObject, id) != null) return Reflect.getProperty(extendedObject, id);
				}
				if (scriptObject != null && (Reflect.hasField(scriptObject, id) || Reflect.getProperty(scriptObject, id) != null)) return Reflect.getProperty(scriptObject, id);
				if (imports.exists(id)) return imports.get(id);
				return null;

			case ECall(target, args):
				var evalArgs = args.map(expr);

				if (target.match(EIdent("trace"))) {
					printMsg(Std.string(evalArgs[0]));
					return null;
				}

				switch (target) {
					case EIdent(methodName):
						if (locals.exists(methodName)) return call(methodName, evalArgs);
						if (extendedObject != null && (Reflect.hasField(extendedObject, methodName) || Reflect.getProperty(extendedObject, methodName) != null)) return Reflect.callMethod(extendedObject, Reflect.getProperty(extendedObject, methodName), evalArgs);
						if (scriptObject != null && (Reflect.hasField(scriptObject, methodName) || Reflect.getProperty(scriptObject, methodName) != null)) return Reflect.callMethod(scriptObject, Reflect.getProperty(scriptObject, methodName), evalArgs);
						JaxeScript.handleError('Method \'$methodName\' not found.', 0, 0, null, scriptName, true);
						return null;

					case EField(EThis, methodName):
						if (extendedObject != null) {
							var instVars = JaxeInterp.instanceVars.get(extendedObject);
							if (instVars != null && instVars.exists(methodName)) return Reflect.callMethod(extendedObject, instVars.get(methodName), evalArgs);
							if (Reflect.hasField(extendedObject, methodName) || Reflect.getProperty(extendedObject, methodName) != null) return Reflect.callMethod(extendedObject, Reflect.getProperty(extendedObject, methodName), evalArgs);
						}
						if (scriptObject != null && (Reflect.hasField(scriptObject, methodName) || Reflect.getProperty(scriptObject, methodName) != null)) return Reflect.callMethod(scriptObject, Reflect.getProperty(scriptObject, methodName), evalArgs);
						if (locals.exists(methodName)) return call(methodName, evalArgs);
						JaxeScript.handleError('Method \'$methodName\' not found on \'this\'.', 0, 0, null, scriptName, true);
						return null;

					case EField(ESuper, methodName):
						var targetObj = extendedObject;
						var cleanName = StringTools.startsWith(methodName, "scripted_") ? methodName.substring(9) : methodName;
						var hookName = cleanName;
						if (targetObj != null && (Reflect.hasField(targetObj, "scripted_" + cleanName) || Reflect.getProperty(targetObj, "scripted_" + cleanName) != null)) hookName = "scripted_" + cleanName;
						if (superMethods.exists(cleanName)) return Reflect.callMethod(targetObj, superMethods.get(cleanName), evalArgs);
						var sFunc = Reflect.getProperty(targetObj, hookName);
						if (sFunc != null) return Reflect.callMethod(targetObj, sFunc, evalArgs);
						JaxeScript.handleError('Super Method \'$methodName\' not found.', 0, 0, null, scriptName, true);
						return null;

					case EField(objExpr, methodName):
						var obj = expr(objExpr);

						if (obj != null && Type.getClassName(Type.getClass(obj)) == "flixel.FlxG" && methodName == "resetState") {
							var newState = JaxeScript.loadClass(this.scriptName);
							if (newState != null) {
								Reflect.callMethod(obj, Reflect.field(obj, "switchState"), [newState]);
								return null;
							}
						}

						if (obj == null) { JaxeScript.handleError('Target object is null when calling $methodName()', 0, 0, null, scriptName, true); return null; }
						var instVars = JaxeInterp.instanceVars.get(obj);
						if (instVars != null && instVars.exists(methodName)) return Reflect.callMethod(obj, instVars.get(methodName), evalArgs);
						var func = Reflect.getProperty(obj, methodName);
						if (func == null) func = Reflect.field(obj, methodName);
						if (func != null) return Reflect.callMethod(obj, func, evalArgs);
						for (u in usings) { var staticFunc = Reflect.getProperty(u, methodName); if (staticFunc != null) { evalArgs.unshift(obj); return Reflect.callMethod(u, staticFunc, evalArgs); } }
						JaxeScript.handleError('Method \'$methodName\' not found on target object.', 0, 0, null, scriptName, true);
						return null;

					default:
						var func = expr(target); if (Reflect.isFunction(func)) return Reflect.callMethod(null, func, evalArgs); return null;
				}

			case EString(s, interpolate):
				if (!interpolate) return s;
				var r = ~/\$\{([^}]+)\}/g; var result = s;
				while (r.match(result)) { var innerRes = expr(new JaxeParser().parseString(r.matched(1) + ";", "interp")[0]); result = r.matchedLeft() + Std.string(innerRes) + r.matchedRight(); r = ~/\$\{([^}]+)\}/g; } return result;

			case EInt(i): return i; case EFloat(f): return f; case EBool(b): return b;
			case EBinop(op, e1, e2):
				var v1:Dynamic = expr(e1); var v2:Dynamic = expr(e2);
				switch (op) { case "+": return v1 + v2; case "-": return v1 - v2; case "*": return v1 * v2; case "/": return v1 / v2; case "%": return v1 % v2; case "==": return v1 == v2; case "!=": return v1 != v2; case ">": return v1 > v2; case "<": return v1 < v2; case ">=": return v1 >= v2; case "<=": return v1 <= v2; case "&&": return v1 && v2; case "||": return v1 || v2; default: return null; }
			default: return null;
		}
	}
}
