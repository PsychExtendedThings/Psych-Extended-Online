package backend;

import flixel.addons.ui.FlxUIState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxState;

#if SCRIPTING_ALLOWED
import funkin.backend.scripting.HScript;
#end

class MusicBeatState extends FlxUIState
{
	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();
	public static function getVariables()
		return getState().variables;

	public static var instance:MusicBeatState;

	/** stops time **/
	private var theWorld:Bool = false;

	public var curSection:Int = 0;
	public var stepsToDo:Int = 0;

	public var curStep:Int = 0;
	public var curBeat:Int = 0;
	public var curStepFloat:Float = 0;
	public var curBeatFloat:Float = 0;
	public static var stepsPerBeat:Float = 4;

	public var curDecStep:Float = 0;
	public var curDecBeat:Float = 0;
	public var controls(get, never):Controls;
	private function get_controls()
	{
		return Controls.instance;
	}
	
	#if !SCRIPTING_ALLOWED
	function new() {
		super();
		mobileManager = new MobileControlManager(this);
	}
	#end

	public var mobileManager:MobileControlManager;
	//makes code less messy & easier to write
	public inline function mobileButtonJustPressed(buttons:Dynamic):Bool {
		return mobileManager?.mobilePad?.justPressed(buttons);
	}
	public inline function mobileButtonPressed(buttons:Dynamic):Bool {
		return mobileManager?.mobilePad?.pressed(buttons);
	}
	public inline function mobileButtonJustReleased(buttons:Dynamic):Bool {
		return mobileManager?.mobilePad?.justReleased(buttons);
	}
	public inline function mobileButtonReleased(buttons:Dynamic):Bool {
		return mobileManager?.mobilePad?.released(buttons);
	}

	override function destroy()
	{
		if (mobileManager != null) mobileManager.destroy();
		#if SCRIPTING_ALLOWED
		call("destroy");
		stateScripts = FlxDestroyUtil.destroy(stateScripts);
		#end

		super.destroy();
	}

	public static var camBeat:FlxCamera;

	override function create() {
		instance = this;
		camBeat = FlxG.camera;
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		#if MODS_ALLOWED Mods.updatedOnState = false; #end

		#if SCRIPTING_ALLOWED
		loadScript();
		#end

		super.create();

		if(!skip) {
			openSubState(new CustomFadeTransition(0.7, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
		timePassedOnState = 0;

		#if SCRIPTING_ALLOWED
		call("create");
		#end
	}

	public static var timePassedOnState:Float = 0;
	override function update(elapsed:Float)
	{
		if (theWorld)
			return super.update(elapsed);

		//everyStep();
		var oldStep:Int = curStep;
		timePassedOnState += elapsed;

		updateCurFloats();
		updateCurStep();
		updateBeat();

		if (oldStep != curStep)
		{
			if(curStep > 0)
				stepHit();

			if(PlayState.SONG != null)
			{
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		if(FlxG.save.data != null) FlxG.save.data.fullscreen = FlxG.fullscreen;
		
		stagesFunc(function(stage:BaseStage) {
			stage.update(elapsed);
		});

		#if SCRIPTING_ALLOWED call("update", [elapsed]); #end

		super.update(elapsed);
	}

	private function updateSection():Void
	{
		if(stepsToDo < 1) stepsToDo = Math.round(getBeatsOnSection() * 4);
		while(curStep >= stepsToDo)
		{
			curSection++;
			var beats:Float = getBeatsOnSection();
			stepsToDo += Math.round(beats * 4);
			sectionHit();
		}
	}

	private function rollbackSection():Void
	{
		if(curStep < 0) return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		for (i in 0...PlayState.SONG.notes.length)
		{
			if (PlayState.SONG.notes[i] != null)
			{
				stepsToDo += Math.round(getBeatsOnSection() * 4);
				if(stepsToDo > curStep) break;
				
				curSection++;
			}
		}

		if(curSection > lastSection) sectionHit();
	}

	private function updateCurFloats():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);
		curStepFloat = lastChange.stepTime + ((Conductor.songPosition - lastChange.songTime) / lastChange.stepCrochet);
		curBeatFloat = curStepFloat / stepsPerBeat;
	}

	private function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
		curDecBeat = curDecStep/4;
	}

	private function updateCurStep():Void
	{
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	// credit to https://github.com/DetectiveBaldi/FNF-PsychEngine/blob/36e982e2e3e78b9b7939ecfff06f5ffdbcd9cca6/source/backend/MusicBeatState.hx
	override function startOutro(onOutroComplete:() -> Void):Void {
		if (!FlxTransitionableState.skipNextTransIn) {
			FlxG.state.openSubState(new CustomFadeTransition(0.6, false));

			CustomFadeTransition.finishCallback = onOutroComplete;

			return;
		}

		FlxTransitionableState.skipNextTransIn = false;

		onOutroComplete();
	}

	public static function getState():MusicBeatState {
		return cast (FlxG.state, MusicBeatState);
	}

	public function stepHit():Void
	{
		stagesFunc(function(stage:BaseStage) {
			stage.curStep = curStep;
			stage.curDecStep = curDecStep;
			stage.stepHit();
		});
		#if GLOBAL_SCRIPT GlobalScript.stepHit(curStep); #end
		call("stepHit", [curStep]);

		if (curStep % 4 == 0)
			beatHit();
	}

	public var stages:Array<BaseStage> = [];
	public function beatHit():Void
	{
		//trace('Beat: ' + curBeat);
		stagesFunc(function(stage:BaseStage) {
			stage.curBeat = curBeat;
			stage.curDecBeat = curDecBeat;
			stage.beatHit();
		});
		#if GLOBAL_SCRIPT GlobalScript.beatHit(curBeat); #end
		call("beatHit", [curBeat]);
	}

	public function sectionHit():Void
	{
		//trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
		stagesFunc(function(stage:BaseStage) {
			stage.curSection = curSection;
			stage.sectionHit();
		});
		call("measureHit", [curSection]);
	}

	function stagesFunc(func:BaseStage->Void)
	{
		for (stage in stages)
			if(stage != null && stage.exists && stage.active)
				func(stage);
	}

	function getBeatsOnSection()
	{
		var val:Null<Float> = 4;
		if(PlayState.SONG != null && PlayState.SONG.notes[curSection] != null) val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? 4 : val;
	}
	
	/* Codename Engine */
	/**
	 * Shortcut to `FlxMath.lerp` or `CoolUtil.lerp`, depending on `fpsSensitive`
	 * @param v1 Value 1
	 * @param v2 Value 2
	 * @param ratio Ratio
	 * @param fpsSensitive Whenever the ratio should not be adjusted to run at the same speed independent of framerate.
	 */
	public function lerp(v1:Float, v2:Float, ratio:Float, fpsSensitive:Bool = false) {
		if (fpsSensitive)
			return FlxMath.lerp(v1, v2, ratio);
		else
			return CoolUtil.fpsLerp(v1, v2, ratio);
	}

	/**
	 * SCRIPTING STUFF
	 */
	#if SCRIPTING_ALLOWED
	public var scriptsAllowed:Bool = true;

	/**
	 * Current injected script attached to the state. To add one, create a file at path "data/states/stateName" (ex: data/states/FreeplayState)
	 */
	public var stateScripts:ScriptPack;

	public static var lastScriptName:String = null;
	public static var lastStateName:String = null;

	public var scriptName:String = null;

	public function new(scriptsAllowed:Bool = true, ?scriptName:String) {
		super();
		mobileManager = new MobileControlManager(this);
		if(lastStateName != (lastStateName = Type.getClassName(Type.getClass(this)))) {
			lastScriptName = null;
		}
		this.scriptName = scriptName != null ? scriptName : lastScriptName;
		lastScriptName = this.scriptName;
	}

	function loadScript(?customPath:String) {
		var className = Type.getClassName(Type.getClass(this));
		if (stateScripts == null)
			(stateScripts = new ScriptPack(className)).setParent(this);
		if (scriptsAllowed) {
			if (stateScripts.scripts.length == 0) {
				var scriptName = this.scriptName != null ? this.scriptName : className.substr(className.lastIndexOf(".")+1);
				var filePath:String = "states/" + scriptName;
				if (customPath != null)
					filePath = customPath;
				var path = Paths.script('data/' + filePath);
				var script = Script.create(path);
				if (script is DummyScript) {
				} else {
					script.remappedNames.set(script.fileName, '${script.fileName}');
					stateScripts.add(script);
					script.load();
					call('create');
				}
			}
		}
	}
	#end

	public function call(name:String, ?args:Array<Dynamic>, ?defaultVal:Dynamic):Dynamic {
		// calls the function on the assigned script
		#if SCRIPTING_ALLOWED
		if(stateScripts != null)
			return stateScripts.call(name, args);
		#end
		return defaultVal;
	}

	public function event(name:String, event:CancellableEvent):CancellableEvent {
		#if SCRIPTING_ALLOWED
		if(stateScripts != null)
			stateScripts.call(name, [event]);
		#end
		return event;
	}

	override function closeSubState() {
		super.closeSubState();
		call('onCloseSubState');
	}

	public function closeSubStatePost() {
		call('onCloseSubStatePost');
	}

	public override function createPost() {
		super.createPost();
		//persistentUpdate = true;
		call("postCreate");
	}

	public override function tryUpdate(elapsed:Float):Void
	{
		if (persistentUpdate || subState == null) {
			call("preUpdate", [elapsed]);
			update(elapsed);
			call("postUpdate", [elapsed]);
		}

		if (_requestSubStateReset)
		{
			_requestSubStateReset = false;
			resetSubState();
		}
		if (subState != null)
		{
			subState.tryUpdate(elapsed);
		}
	}

	public override function onFocus() {
		super.onFocus();
		call("onFocus");
	}

	public override function onFocusLost() {
		super.onFocusLost();
		call("onFocusLost");
	}
}
