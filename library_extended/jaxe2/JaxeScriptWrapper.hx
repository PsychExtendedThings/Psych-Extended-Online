package jaxe;

#if sys
import sys.io.File;
import sys.FileSystem;
#end
import haxe.io.Path;
import jaxe.JaxeScript;

using StringTools;

/**
 * A lightweight, simple wrapper for loading and running individual Jaxe scripts.
 */
class JaxeScriptWrapper {
	public var backend:JaxeScript;
	public var active:Bool = true;
	public var scriptPath:String;
	public var fileName:String;

	public function new(path:String, ?parentObj:Dynamic) {
		this.scriptPath = path;
		this.fileName = Path.withoutDirectory(path);

		#if sys
		if (FileSystem.exists(path)) {
			var code = File.getContent(path);
			backend = new JaxeScript(code);
			backend.scriptName = fileName;

			if (parentObj != null) {
				backend.setParent(parentObj);
			}

			for (k => v in getDefaultVariables()) {
				backend.set(k, v);
			}

			backend.run();
		} else {
			trace('Jaxe Error: Script not found at normal path -> $path');
		}
		#else
		trace("Jaxe Error: File system access requires a sys target (Windows/Mac/Linux/Android).");
		#end
	}

	/**
	 * Calls a specific function inside the script.
	 */
	public function call(funcName:String, args:Array<Dynamic> = null):Dynamic {
		if (!active || backend == null) return null;
		return backend.call(funcName, args != null ? args : []);
	}

	/**
	 * Injects a custom variable or object into this script.
	 */
	public function set(varName:String, value:Dynamic):Void {
		if (backend != null) {
			backend.set(varName, value);
		}
	}

	/**
	 * A much cleaner, simpler list of essential default FNF classes.
	 */
	public static function getDefaultVariables():Map<String, Dynamic> {
		return [
			"Math"	  => Math,
			"Std"	   => Std,
			"FlxG"	  => flixel.FlxG,
			"FlxSprite" => flixel.FlxSprite,
			"FlxMath"   => flixel.math.FlxMath,
			"FlxTween"  => flixel.tweens.FlxTween,
			"FlxEase"   => flixel.tweens.FlxEase,
			"FlxTimer"  => flixel.util.FlxTimer
		];
	}
}


/**
 * Manages multiple Jaxe scripts and broadcasts function calls to all of them.
 */
class JaxeManager {
	public var scripts:Array<JaxeScriptWrapper> = [];

	public function new() {}

	/**
	 * Loads a single script by its normal file path.
	 */
	public function loadScript(path:String, ?parentObj:Dynamic):JaxeScriptWrapper {
		var script = new JaxeScriptWrapper(path, parentObj);

		scripts.push(script);
		return script;
	}

	/**
	 * Loads all .java and .jaxe files inside a normal directory path.
	 */
	public function loadFolder(folderPath:String, ?parentObj:Dynamic):Void {
		#if sys
		if (FileSystem.exists(folderPath) && FileSystem.isDirectory(folderPath)) {
			for (file in FileSystem.readDirectory(folderPath)) {
				if (file.endsWith(".java") || file.endsWith(".jaxe")) {
					loadScript(folderPath + "/" + file, parentObj);
				}
			}
		} else {
			trace('JaxeManager: Folder not found -> $folderPath');
		}
		#end
	}

	/**
	 * Broadcasts a function call to EVERY active script.
	 * Example: callAll("update", [elapsed]);
	 */
	public function callAll(funcName:String, args:Array<Dynamic> = null):Void {
		for (script in scripts) {
			//if (script.active) {
				script.call(funcName, args);
			//}
		}
	}

	/**
	 * Sets a variable in EVERY active script.
	 * Example: setAll("boyfriend", PlayState.instance.boyfriend);
	 */
	public function setAll(varName:String, value:Dynamic):Void {
		for (script in scripts) {
			script.set(varName, value);
		}
	}

	/**
	 * Clears all scripts from memory.
	 */
	public function destroy():Void {
		scripts = [];
	}
}
