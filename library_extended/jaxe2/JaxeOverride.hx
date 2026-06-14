package jaxe;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Type;
import jaxe.JaxeConfig;

using StringTools;
using Lambda;

class JaxeOverride {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var localClass = Context.getLocalClass().get();
		var pack = localClass.pack.join(".");
		var fullClassName = (pack.length > 0 ? pack + "." : "") + localClass.name;

		for (ignored in JaxeConfig.DISALLOW_OVERRIDE_CLASSES) {
			if (fullClassName.startsWith(ignored) || localClass.name.startsWith(ignored)) return fields;
		}

		if (localClass.meta.has(":jaxeProcessed")) return fields;
		localClass.meta.add(":jaxeProcessed", [], localClass.pos);

		var newFields:Array<Field> = [];
		var processedNames:Array<String> = [for (f in fields) f.name];

		function parentHasJaxeField(fieldName:String):Bool {
			var cl = localClass.superClass;
			while (cl != null) {
				var t = cl.t.get();
				if (t.meta.has(":jaxeProcessed")) {
					for (f in t.fields.get()) {
						if (f.name == fieldName) return true;
					}
				}
				cl = t.superClass;
			}
			return false;
		}

		var targetClass = localClass;
		while (targetClass != null) {
			for (field in targetClass.fields.get()) {
				var name = field.name;

				if (processedNames.contains(name) || name.startsWith("__") || name == "hget" || name == "hset" || name == "new") continue;

				switch (field.type) {
					case TFun(args, ret):
						var complexRet = Context.toComplexType(ret);
						var funcArgs:Array<FunctionArg> = [for (arg in args) {
							name: arg.name,
							opt: arg.opt,
							type: Context.toComplexType(arg.t)
						}];
						var callArgs:Array<Expr> = [for (arg in args) macro $i{arg.name}];

						var superName = "super_" + name;
						var scriptedName = "scripted_" + name;

						var hasParentSuper = parentHasJaxeField(superName);
						var hasParentScripted = parentHasJaxeField(scriptedName);

						// Handle the body for overrides
						var originalCode:Expr;
						if (targetClass == localClass) {
							// If the function is defined IN this class, find its original expression
							var localField = fields.find(f -> f.name == name);
							if (localField != null) {
								switch (localField.kind) {
									case FFun(f): 
										originalCode = f.expr;
										// Patch the local function to redirect to the scripted version
										f.expr = macro return this.$scriptedName($a{callArgs});
									default: originalCode = macro super.$name($a{callArgs});
								}
							} else {
								originalCode = macro super.$name($a{callArgs});
							}
						} else {
							originalCode = macro super.$name($a{callArgs});
						}

						var superAccess:Array<Access> = [APublic];
						if (hasParentSuper) superAccess.push(AOverride);
						
						newFields.push({
							name: superName,
							access: superAccess,
							kind: FFun({
								args: funcArgs,
								ret: complexRet,
								expr: originalCode
							}),
							pos: field.pos
						});

						var scriptedAccess:Array<Access> = [APublic, ADynamic];
						if (hasParentScripted) scriptedAccess.push(AOverride);

						newFields.push({
							name: scriptedName,
							access: scriptedAccess,
							kind: FFun({
								args: funcArgs,
								ret: complexRet,
								expr: macro return this.$superName($a{callArgs})
							}),
							pos: field.pos
						});

						if (targetClass != localClass) {
							fields.push({
								name: name,
								access: [APublic, AOverride],
								kind: FFun({
									args: funcArgs,
									ret: complexRet,
									expr: macro return this.$scriptedName($a{callArgs})
								}),
								pos: field.pos
							});
						}

						processedNames.push(name);
					default:
				}
			}
			targetClass = (targetClass.superClass != null) ? targetClass.superClass.t.get() : null;
		}

		return fields.concat(newFields);
	}
}
