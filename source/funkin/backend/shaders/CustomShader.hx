package funkin.backend.shaders;

import haxe.Exception;
import openfl.Assets;
#if (HSC_ALLOWED || SCRIPTING_ALLOWED)
import codenamecrew.hscript.IHScriptCustomBehaviour;
#else
import hscriptBase.IHScriptCustomBehaviour;
#end

/**
 * Class for custom shaders from Codename Engine, Added for Using Shaders in PsychEngine without any shitty code.
 *
 * To create one, create a `shaders` folder in your mod folder, then add a file named `my-shader.frag` or/and `my-shader.vert`.
 *
 * Non-existent shaders will only load the default one, and throw a warning in the console.
 *
 * To access the shader's uniform variables, use `shader.variable`
 */
class CustomShader extends FunkinShader {
	public var path:String = "";

	/**
	 * Creates a new custom shader
	 * @param name Name of the frag and vert files.
	 * @param glslVersion GLSL version to use. Defaults to `100` in mobile, `120` in desktop.
	 */
	public function new(name:String, glslVersion:String = #if mobile "100" #else "120" #end) {
		var fragShaderPath = Paths.fragShaderPath(name);
		var vertShaderPath = Paths.vertShaderPath(name);
		var fragCode = Paths.fileExists('shaders/$name.frag', TEXT) ? Paths.fragShader(name) : null;
		var vertCode = Paths.fileExists('shaders/$name.vert', TEXT) ? Paths.vertShader(name) : null;

		fragFileName = fragShaderPath;
		vertFileName = vertShaderPath;

		path = fragShaderPath+vertShaderPath;

		if (fragCode == null && vertCode == null)
			CoolUtil.showPopUp('Shader "$fragShaderPath" and "$vertShaderPath" couldn\'t be found.', "ERROR");

		super(fragCode, vertCode, glslVersion);
	}
}