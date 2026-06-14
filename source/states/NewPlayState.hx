package states;

// If you want to add your stage to the game, copy states/stages/Template.hx,
// and put your stage code there, then, on PlayState, search for
// "switch (curStage)", and add your stage to that list.

// If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
// "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
// "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
// "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
// "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for

import online.s3d.FunkinStage3D;
import haxe.ds.HashMap;
import online.substates.PostTextSubstate;
import haxe.crypto.Md5;
import online.network.FunkinNetwork;
import online.objects.InputText;
import online.replay.ReplayRecorder.ReplayData;
import online.replay.*;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Lib;
import flixel.util.FlxSpriteUtil;
import flixel.group.FlxGroup;
import flixel.addons.util.FlxAsyncLoop;
import flixel.effects.FlxFlicker;
import online.objects.LeavePie;
import online.objects.ChatBox;
import online.gui.LoadingScreen;
import online.gui.Alert;
import online.backend.Waiter;
import online.states.RoomState;
import online.GameClient;
import online.objects.NicommentsView;
import backend.Achievements;
import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Section;
import backend.Rating;
import lime.media.openal.AL;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import tjson.TJSON as Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;

#if !flash 
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if VIDEOS_ALLOWED 
#if hxCodec
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideo as VideoHandler;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoHandler as VideoHandler;
#elseif (hxCodec == "2.6.0") import VideoHandler;
#else import vlc.MP4Handler as VideoHandler; #end
#end
#end

#if HSC_ALLOWED
import funkin.backend.scripting.events.CountdownEvent;
#end

import objects.Note.EventNote;
import objects.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.FunkinLua;
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if HSCRIPT_ALLOWED
import tea.SScript;
#end

import online.backend.schema.Player;
import objects.StrumLine;

@:build(online.backend.Macros.getSetForwarder())
class PlayState extends MusicBeatState
{
	/**
	 * Speed at which the game camera zoom lerps to.
	 */
	public var camGameZoomLerp:Float = 0.05;
	/**
	 * Speed at which the hud camera zoom lerps to.
	 */
	public var camHUDZoomLerp:Float = 0.05;

	@:dox(hide)
	public var __updateNote_event:NoteUpdateEvent = null;

	@:isVar public var scrollSpeed(get, set):Float;
	private function get_scrollSpeed() {
		return songSpeed;
	}
	private function set_scrollSpeed(value:Float) {
		songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * value;
		scrollSpeed = songSpeed;
		return songSpeed;
	}

	/**
	 * Current camera target. -1 means no automatic camera targetting.
	 * makes easier to change position shits
	 */
	public var curCameraTarget:Int = 0;

	#if HSC_ALLOWED
	/**
	 * Script Pack of all the scripts being ran.
	 */
	public var scripts:ScriptPack;
	#end
	/**
	 * The selected difficulty name.
	 */
	public static var difficulty(get, never):String;
	private static function get_difficulty() {
		return Difficulty.getString();
	}

	// use only for mod compatibility
	@:deprecated public static var STRUM_X = 42;
	@:deprecated public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];

	//event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();
	
	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	#if LUA_ALLOWED
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var modchartSprites:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public static var opponentMode:Bool = false;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI:String = "normal";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel";

	public static var SONG(default, null):SwagSong;

	public static function loadSong(jsonInput:String, ?folder:String):SwagSong {
		RAW_SONG = Song.loadRawSong(jsonInput, folder);
		return SONG = Song.parseRawJSON(jsonInput, RAW_SONG);
	}

	public static function loadSongFromSwag(v:SwagSong):SwagSong {
		RAW_SONG = haxe.Json.stringify(v);
		return SONG = Song.parseRawJSON('', RAW_SONG);
	}
	
	public static var RAW_SONG:String = ''; 
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;
	public static var isErect:Bool = false;

	public var songSuffix(default, set):String = '';
	function set_songSuffix(v) {
		songSuffix = "";
		if (v.trim().length > 0 && !v.startsWith("-"))
			songSuffix += "-";
		songSuffix += v;
		return songSuffix;
	}

	public var spawnTime:Float = 2000;

	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;
	public var inst:FlxSound;

	// dad
	@:isVar public var dad(default, set):Character;
	private function set_dad(dad:Character):Character {
		this.dad = dad;
		if (strumLines != null && strumLines?.members[0] != null)
			strumLines.members[0].characters = [this.dad];
		return dad;
	}

	// boyfriend
	@:isVar public var boyfriend(default, set):Character;
	private function set_boyfriend(bf:Character):Character {
		this.boyfriend = bf;
		if (strumLines != null && strumLines?.members[1] != null)
			strumLines.members[1].characters = [this.boyfriend];
		return bf;
	}

	// girlfriend
	@:isVar public var gf(default, set):Null<Character>;
	private function set_gf(gf:Character):Null<Character> {
		this.gf = gf;
		if (strumLines != null && strumLines?.members[2] != null)
			strumLines.members[2].characters = [this.gf];
		return gf;
	}

	public var dummy:Character = null;
	//its you
	public var self(get, never):Character;

	public var isNulledBf:Bool = false;
	public var isNulledDad:Bool = false;

	//online characters, the map is empty on offline play
	public var characters:Map<String, Character> = new Map();
	public var onlineStrumlines:Map<String, Map<Int, Array<Character>>> = new Map();

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	//Handles the new epic mega sexy cam code that i've done (EDIT: merged with 0.7 cameras -KralOyuncu)
	public var camFollow:Dynamic;
	public var camFollowPos:Dynamic;
	private static var prevCamFollow:FlxPoint;
	private static var prevCamFollowPos:FlxObject;

	/**
	 * Current CNE Stage.
	 */
	public var stage:Stage;

	public var strumLineNotes:StrumLine;
	public var strumLines:FlxTypedGroup<StrumLine> = new FlxTypedGroup<StrumLine>(); //A variable for CNE mods
	public var cpuStrums(get, null):StrumLine;
	private inline function get_cpuStrums():StrumLine
		return strumLines.members[0];
	public var opponentStrums(get, null):StrumLine;
	private inline function get_opponentStrums():StrumLine
		return strumLines.members[0];
	public var playerStrums(get, null):StrumLine;
	private inline function get_playerStrums():StrumLine
		return strumLines.members[1];

	public var grpHoldSplashes:FlxTypedGroup<SustainSplash>;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;

	public static final DEFAULT_BOP_INTENSITY:Float = 1.015;
	public static final DEFAULT_ZOOM_RATE:Int = 4;

	public var cameraBopIntensity:Float = DEFAULT_BOP_INTENSITY;
	public var hudCameraZoomIntensity:Float = 0.015 * 2.0;
	public var cameraZoomRate:Int = DEFAULT_ZOOM_RATE;
	public var camZoomingStrength:Int = 1;
	public var camZoomingInterval:Int = 4;
	public var maxCamZoom:Float = 1.35;

	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	var _prevOHealth:Float = 1;
	@:isVar public var health(get, set):Float = 1;
	function get_health() {
		if (GameClient.isConnected()) {
			if (_prevOHealth != GameClient.room.state.health && gf != null)
				gf.onHealth(_prevOHealth, GameClient.room.state.health);

			// without @:bypassAccessor it'll just loop between the getter and setter constantly (until it crashes)
			return @:bypassAccessor health = _prevOHealth = GameClient.room.state.health;
		}
		return health;
	}
	function set_health(v) {
		if (gf != null)
			gf.onHealth(@:bypassAccessor health, v);

		if (GameClient.isConnected()) {
			return health = GameClient.room.state.health;
		}
		return health = v;
	}

	public var maxCombo(default, null):Int = 0;
	@:unreflective function set_combo(v:Int):Int {
		if (gf != null)
			gf.onCombo(combo, v);
		maxCombo = Math.floor(Math.max(maxCombo, v));
		return combo = v;
	}
	public var combo(default, set):Int = 0;

	public var healthBar:HealthBar;
	public var timeBar:HealthBar;
	var songPercent:Float = 0;

	@:forwardField(healthBar.bg)
	@:deprecated public var healthBarBG(get, set):FlxSprite;
	@:forwardField(timeBar.bg)
	@:deprecated public var timeBarBG(get, set):FlxSprite;

	public var ratingsData:Array<Rating> = Rating.loadDefault();
	public var fullComboFunction:Void->Void = null;

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled(default, set):Bool = false;
	function set_cpuControlled(v):Bool {
		if (GameClient.isConnected()) {
			if (cpuControlled)
				return cpuControlled;

			if (v)
				GameClient.send("botplay");
		}

		cpuControlled = v;
		showBotplay();
		return cpuControlled;
	}
	public var practiceMode:Bool = false;
	public var noBadNotes:Bool = false;
	public var maniaModifier:Null<Int>;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconOriginalScale:Float = 1.0;
	public var iconZoomIntensity:Float = 1.2;
	public var iconP1:HealthIcon;
	public var iconP1s:Array<HealthIcon> = [];
	public var iconP2:HealthIcon;
	public var iconP2s:Array<HealthIcon> = [];
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var camLoading:FlxCamera;
	public var cameraSpeed:Float = 1;

	var _tempDiff:Float = 0;
	public var songScore(default, set):Int = 0;
	function set_songScore(v) {
		_tempDiff = v - songScore;
		_tempDiff *= Math.min(1, playbackRate);
		_tempDiff *= 1 + Math.max(0, combo - 1) * 0.001;
		return songScore += Math.floor(_tempDiff);
	}
	public var songHits(default, set):Int = 0;
	function set_songHits(v) {
		if (v < songHits)
			return v;
		return songHits = v;
	}
	public var songMisses(default, set):Int = 0;
	function set_songMisses(v) {
		if (v < songMisses)
			return v;
		return songMisses = v;
	}
	public var songSicks(default, null):Int = 0;
	public var songGoods(default, null):Int = 0;
	public var songBads(default, null):Int = 0;
	public var songShits(default, null):Int = 0;
	public var songPoints(default, null):Float = 0;

	public var pointsPercent:Float = 0;

	static var COLOR_SICK:FlxColor = 0x6CFD8E;
	static var COLOR_GOOD:FlxColor = 0x68D5FD;
	static var COLOR_BAD:FlxColor = 0xFCD768;
	static var COLOR_SHIT:FlxColor = 0xFC6B68;

	public var scoreTxt:FlxText;
	public var scoreTxtOthers:Map<String, FlxText> = new Map();
	public var scoreTxtOthersTween:Map<String, FlxTween> = new Map();
	public var scoreTxtP1:FlxText;
	public var scoreTxtP2:FlxText;
	var scoreTxtOriginY:Float = 700;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;
	public var defaultHUDCamZoom:Float = 1;
	public var forceCameraZoom(get, set):Float;
	function get_forceCameraZoom() {
		return defaultCamZoom;
	}
	function set_forceCameraZoom(v) {
		FlxG.camera.zoom = v;
		defaultCamZoom = v;
		return v;
	}

	public var currentCameraX(get, set):Float;
	function get_currentCameraX() {
		return camFollow.x;
	}
	function set_currentCameraX(v) {
		FlxG.camera.scroll.x = v;
		camFollow.x = v;
		return v;
	}

	public var currentCameraY(get, set):Float;
	function get_currentCameraY() {
		return camFollow.y;
	}
	function set_currentCameraY(v) {
		FlxG.camera.scroll.y = v;
		camFollow.y = v;
		return v;
	}

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations(get, set):Array<String>;
	var _singAnimations:Array<String>;
	var _singAnimations_keys:Int = -1;
	var _singAnimations_colDirs = [
		'purple' => 'singLEFT', 
		'blue' => 'singDOWN', 
		'odd' => 'singODD', 
		'green' => 'singUP', 
		'red' => 'singRIGHT'
	];
	function get_singAnimations() {
		if (Note.maniaKeys == _singAnimations_keys) {
			return _singAnimations;
		}

		_singAnimations_keys = Note.maniaKeys;
		_singAnimations = [];
		for (key in 0...Note.maniaKeys) {
			_singAnimations.push(_singAnimations_colDirs.get(Note.getColArrayFromKeys()[key]));
		}
		return _singAnimations;
	}
	function set_singAnimations(v) {
		return _singAnimations = v;
	}
	
	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	public var luaArray:Array<FunkinLua> = [];
	#if LUA_ALLOWED
	private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';
	public var skinsSuffix:String = '';

	// Less laggy controls
	public var keysArray:Array<String>;

	public var precacheList:Map<String, String> = new Map<String, String>();
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	var chatBox:ChatBox;
	// var leavePie:LeavePie;

	static var swingMode:Bool = false;

	public var stage3D:FunkinStage3D;

	function checkCanInput() {
		if (chatBox != null && chatBox.focused) {
			return false;
		}
		return true;
	}

	var freakyFlicker:FlxFlicker;
	var readyTween:FlxTween;
	var waitReady(default, set) = false;
	var isReady = false;
	var canStart = true;
	function set_waitReady(v) {
		if (readyTween != null)
			readyTween.cancel();
		if (freakyFlicker?.timer != null)
			freakyFlicker.stop();

		if (waitReadySpr != null)
			readyTween = FlxTween.tween(waitReadySpr, {alpha: v ? 1 : 0}, 0.5, {ease: FlxEase.quadIn});

		paused = v;

		return waitReady = v;
	}
	var waitReadySpr:Alphabet;

	public var songDensity:Float = 0;

	public var stageData:StageFile;
	var stageModDir:String;
	var oldModDir:String;
	var showTime:Bool;
	var camPos:FlxPoint;
	var asyncLoop:FlxAsyncLoop;
	var isCreated:Bool = false;
	var stageExists:Bool = false;
	public static var orderOffset:Int = 0;

	public static var replayData(default, set):ReplayData;
	public static var replayID:String = null;
	static function set_replayData(v) {
		replayID = null;
		return replayData = v;
	}
	public var replayRecorder:ReplayRecorder;
	public var replayPlayer:ReplayPlayer;
	public var nicomments:NicommentsView;
	
	public var songId:String = null;

	@:unreflective
	public static var redditMod:Bool = false;

	var forcePause = false;

	var noteUnderlays:FlxTypedGroup<FlxSprite>;

	public var playOtherSide:Bool = false;

	var nameplates:FlxTypedGroup<FlxText> = new FlxTypedGroup<FlxText>();

	var canSpaceTaunt:Bool = true;

	public function initStrumLineCharacter(startX:Int = 0, startY:Int = 0, charName:String, isRight:Bool, ?type:Int, ?addToHealthBar:Bool, ?player:Player, ?sid:String) {
		var char:Character = null;
		oldModDir = Mods.currentModDirectory;
		var tag:String = null;
		switch (type) {
			case 0:
				tag = "dad";
			case 1:
				tag = "bf";
			case 2:
				tag = "gf";
		}
		var charPosName:String = "penci zorno";
		switch(type) {
			case 0: charPosName = "dad";
			case 1: charPosName = "boyfriend";
			case 2: charPosName = "girlfriend";
		}

		var shouldFlipX:Bool = (stage != null) ? stage.isCharFlipped(charPosName, isRight) : isRight;

		function songPlayerMatchesSkin(skin:String) {
            return charName.startsWith(skin);
        }

        if (player != null) {
            if (player.skin.length > 0 && !songPlayerMatchesSkin(player.skin.items[0])) {
                Mods.currentModDirectory = player.skin.items[3];
                char = new Character(startX, startY, player.skin.items[0] + skinsSuffix + player.skin.items[isRight ? 2 : 1], shouldFlipX, true, tag);
            }
        }
        else if (playsAsBF() == isRight && ClientPrefs.data.currentSkin != null && !songPlayerMatchesSkin(ClientPrefs.data.currentSkin[0])) {
            Mods.currentModDirectory = ClientPrefs.data.currentSkin[3];
            char = new Character(startX, startY, ClientPrefs.data.currentSkin[0] + skinsSuffix + ClientPrefs.data.currentSkin[isRight ? 2 : 1], shouldFlipX, true, tag);
        }

        if (char != null && charName.endsWith('-blazin') && !char.curCharacter.endsWith('-blazin')) {
            char.destroy();
            char = null;
        }

        if (char == null || char.loadFailed) {
            if (char != null) {
                Mods.currentModDirectory = oldModDir;
            }

            if (stage != null)
                char = new Character(startX, startY, charName, shouldFlipX, false, tag);
            else
                char = new Character(startX, startY, charName, shouldFlipX, false, tag);

            if (char.loadFailed) {
                for (suffix in (isRight ? online.states.SkinsState.RIGHT_SUFFIX : online.states.SkinsState.LEFT_SUFFIX)) {
                    final charExists = Character.getCharacterFile(charName + suffix, null, true) != null;
                    if (charExists) {
                        char = new Character(startX, startY, charName + suffix, shouldFlipX, false, tag);
                        break;
                    }
                }
            }
        }

        char.ox = player?.ox ?? 0;

        if (addToHealthBar) {
            if (isRight) {
                if (boyfriend == null || char.ox == 0)
                    boyfriend = char;

                var icon = new HealthIcon(char.healthIcon, true);
                icon.ox = char.ox;

                if (iconP1 == null)
                    iconP1 = icon;

                char.gameIconIndex = iconP1s.length;
                iconP1s.push(icon);
            }
            else {
                if (dad == null || char.ox == 0)
                    dad = char;

                var icon = new HealthIcon(char.healthIcon, false);
                icon.ox = char.ox;

                if (iconP2 == null)
                    iconP2 = icon;

                char.gameIconIndex = iconP2s.length;
                iconP2s.push(icon);
            }
        }

        if (!playsAsBF()) {
            char.flipX = !char.flipX;
        }

        if (stage == null) startCharacterPos(char, !isRight);
        
        switch (tag) {
            case "dad":
                if (stage != null) add(char);
                else dadGroup.add(char);
            case "bf":
                if (stage != null) add(char);
                else boyfriendGroup.add(char);
            case "gf":
                if (stage != null) add(char);
                else gfGroup.add(char);
            default:
                add(char);
        }
        
        if (stage != null) stage.applyCharStuff(char, isRight ? "boyfriend" : "dad", 0);

        startCharacterScripts(char.curCharacter, sid, isRight);

		var strumIndex = type;
		if (strumIndex == null) strumIndex = isRight ? 1 : 0;
		if (!onlineStrumlines.exists(sid)) {
			onlineStrumlines.set(sid, new Map());
		}
		var sidMap = onlineStrumlines.get(sid);
		if (sidMap.exists(strumIndex)) {
			sidMap.get(strumIndex).push(char);
		} else {
			sidMap.set(strumIndex, [char]);
		}

        Mods.currentModDirectory = oldModDir;

        return char;
    }

	//backwards compatibility
	public function addStrum(isCPU:Bool, targetCharacters:Array<Character>, targetNoteData:Int, ?amount:Null<Int>) {
		addTextToDebug("addStrum: this code deprecated, use createStrum for avoiding this message", FlxColor.YELLOW);
		createStrum(isCPU, targetCharacters, true, amount);
	}

	public function createStrum(isCPU:Bool, targetCharacters:Array<Character>, ?startVisibilty:Bool = true, ?amount:Null<Int>) {
		if (amount == null) amount = Note.maniaKeys;

		var strumWidth = amount * Note.swagScaledWidth - (Note.getNoteOffsetX() * (amount - 1));
		var strumLineX:Float = 0;

		if (ClientPrefs.data.middleScroll) {
			strumLineX = FlxG.width / 2 - strumWidth / 2;
		}
		else {
			strumLineX = (FlxG.width / 2 - strumWidth) / 2;
			strumLineX += FlxG.width / 2 * (isCPU ? 0 : 1);
		}

		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		var strumGroup:StrumLine = new StrumLine(isCPU, targetCharacters, amount);
		strumGroup.cameras = [camHUD];
		strumLines.add(strumGroup);

		for (i in 0...amount)
		{
			var targetAlpha:Float = 1;

			if (!isPlayerStrumNote(isCPU ? 0 : 1))
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, isCPU ? 0 : 1);
			babyArrow.forceShow = ClientPrefs.data.opponentStrums && ClientPrefs.data.disableStrumMovement;
			babyArrow.downScroll = ClientPrefs.data.downScroll;
	
			var event = EventManager.get(StrumCreationEvent).recycle(babyArrow, strumLines.members.indexOf(strumGroup), i);
			event.__doAnimation = true;
			event = scripts.event("onStrumCreation", event);

			if (!isStoryMode && !skipArrowStartTween && event.__doAnimation)
			{
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + 4 / amount * 0.2 * i});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (!isPlayerStrumNote(isCPU ? 0 : 1) && ClientPrefs.data.middleScroll) {
				babyArrow.x = strumLineX / 2 - strumWidth / 4;
				if (i > amount / 2 - 1) { // half rest
					babyArrow.x += (strumLineX + strumWidth / 2);
				}

				if (amount % 2 != 0 && i == Std.int(amount / 2)) {
					babyArrow.forceHide = true;
				}
			}

			scripts.event("onPostStrumCreation", event);

			babyArrow.visible = startVisibilty;
			strumGroup.add(babyArrow);
			if (replayPlayer == null && ClientPrefs.data.noteUnderlayOpacity > 0 && strumGroup == getPlayerStrums(true) && ClientPrefs.data.noteUnderlayType == 'By Note') {
				var underlay = new FlxSprite().makeGraphic(1, FlxG.width * 2, FlxColor.BLACK);
				underlay.alpha = ClientPrefs.data.noteUnderlayOpacity;
				underlay.scale.x = Note.swagScaledWidth;
				underlay.updateHitbox();
				noteUnderlays.add(underlay);
			}

			if (GameClient.isConnected()) {
				if (!playsAsBF())
					babyArrow.maxAlpha = (isCPU ? 1 : 0.7);
				else
					babyArrow.maxAlpha = (isCPU ? 0.7 : 1);
			}

			//strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();
		}
		return strumGroup;
	}

	override public function create()
	{
		// for lua
		instance = this;

		theWorld = true;

		Conductor.judgeSongPosition = null;
		Conductor.judgePlaybackRate = null;

		var duoOpponentSID = null;
		if (GameClient.isConnected()) {
			#if windows
			Lib.application.window.resizable = false;
			#end
			swingMode = false;
			isDuel = GameClient.room.state.players.length <= 2;
			@:bypassAccessor waitReady = true;
			if (isDuel) {
				for (sid => player in GameClient.room.state.players) {
					if (sid != GameClient.room.sessionId) {
						opponentPlayer = player;
						duoOpponentSID = sid;
					}
				}
			}
		}

		Paths.clearUnusedMemory();
		Paths.clearStoredMemory();

		//Load Mobile Shit (Makes Testing The Hitboxes Easier)
		MobileConfig.init('MobileControls', CoolUtil.getSavePath(), 'assets/mobile/',
			[
				['MobilePad/DPadModes', ButtonModes.DPAD],
				['MobilePad/ActionModes', ButtonModes.ACTION],
				['Hitbox/HitboxModes', ButtonModes.HITBOX]
			]
		);

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camLoading = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.add(camLoading, false);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		FlxG.cameras.cameraAdded.addOnce(realignLoadCam);

		CustomFadeTransition.nextCamera = camLoading;
		camGame.bgColor = FlxColor.TRANSPARENT;

		isErect = Difficulty.getString() == "Erect" || Difficulty.getString() == "Nightmare";
		songSuffix = isErect ? "erect" : "";


		canPause = !redditMod; // !(GameClient.isConnected() || redditMod);
		canStart = !GameClient.isConnected();

		(scripts = new ScriptPack("PlayState")).setParent(this);

		var preloadTasks:Array<Void->Void> = [];

		preloadTasks.push(() -> {
			// trace('Playback Rate: ' + playbackRate);

			startCallback = startCountdown;
			endCallback = () -> {
				finishingSong = true;
				endSong();
			};

			if (GameClient.isConnected()) {
				paused = true;
				GameClient.send("status", Language.getText("In-Game"));
			}
		});

		preloadTasks.push(() -> {
			if (GameClient.isConnected())
				replayData = null;

			PauseSubState.songName = null; // Reset to default
			playbackRate = ClientPrefs.getGameplaySetting('songspeed');
			fullComboFunction = fullComboUpdate;

			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();

			// Gameplay settings
			healthGain = ClientPrefs.getGameplaySetting('healthgain');
			healthLoss = ClientPrefs.getGameplaySetting('healthloss');
			instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
			practiceMode = ClientPrefs.getGameplaySetting('practice');
			cpuControlled = ClientPrefs.getGameplaySetting('botplay');
			opponentMode = ClientPrefs.getGameplaySetting('opponentplay');
			noBadNotes = ClientPrefs.getGameplaySetting('nobadnotes');
			if (Note.maniaKeysStringList.contains(ClientPrefs.getGameplaySetting('mania'))) {
				maniaModifier = Std.parseInt(ClientPrefs.getGameplaySetting('mania').split('k')[0]);
			}
		});

		preloadTasks.push(() -> {
			grpHoldSplashes = new FlxTypedGroup<SustainSplash>();
			grpNoteSplashes = new FlxTypedGroup<NoteSplash>();

			persistentUpdate = true;
			persistentDraw = true;
		});

		preloadTasks.push(() -> {
			if (SONG == null)
				loadSong('tutorial');

			Conductor.mapBPMChanges(SONG);
			Conductor.bpm = SONG.bpm;

			songId = FreeplayState.filterCharacters(PlayState.SONG.song) + "-" +
				FreeplayState.filterCharacters(Difficulty.getString()) + "-" + 
				FreeplayState.filterCharacters(Md5.encode(PlayState.RAW_SONG))
			;

			#if DISCORD_ALLOWED
			storyDifficultyText = Difficulty.getString();
			#end

			#if DISCORD_ALLOWED
			// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
			if (GameClient.isConnected()) {
				if (!GameClient.room.state.isPrivate)
					detailsText = Language.getText("Playing a online game!");
				else
					detailsText = Language.getText("Playing a online private game!");
			}
			else if (isStoryMode)
				detailsText = Language.getText("Story Mode: ") + WeekData.getCurrentWeek().weekName;
			else {
				if (replayData != null)
					detailsText = replayData.player + Language.getText("'s Replay");
				else
					detailsText = Language.getText("Freeplay");
			}

			// String for when the game is paused
			detailsPausedText = Language.getText("Paused - ") + detailsText;
			#end

			GameOverSubstate.resetVariables();
			songName = Paths.formatToSongPath(SONG.song);
		});

		preloadTasks.push(() -> {
			stageModDir = Mods.currentModDirectory; // thats a big woops 
			oldModDir = Mods.currentModDirectory;

			var swagStage = SONG.stage;

			if (GameClient.isConnected() && GameClient.room.state.stageName != '') {
				swagStage = GameClient.room.state.stageName;
				if (GameClient.room.state.stageMod != '')
					Mods.currentModDirectory = stageModDir = GameClient.room.state.stageMod;
			}

			if (swagStage == null || swagStage.length < 1) {
				swagStage = StageData.vanillaSongStage(songName);
			}

			if ((isErect || (SONG.song.endsWith(' Pico'))) && ( //sorry
				swagStage == 'stage' ||
				swagStage == 'spooky' ||
				swagStage == 'philly' ||
				swagStage == 'limo' ||
				swagStage == 'mall' ||
				swagStage == 'school' ||
				swagStage == 'tank'
			)) {
				swagStage = swagStage + '-erect';
			}
			curStage = swagStage;

			stageData = StageData.getStageFile(curStage);
			var cneStageFile:String = Paths.getPath('data/stages/$curStage.xml', TEXT, null, true);
			if (stageData == null && FunkinFileSystem.exists(cneStageFile)) {
				trace("found lol");
				stageData = StageData.dummy(); //for test
				add(stage = new Stage(curStage));
			}
			else if (stageData == null) { // Stage couldn't be found, create a dummy stage for preventing a crash
				stageData = StageData.dummy();
			}

			Mods.currentModDirectory = oldModDir;
			Paths.setCurrentLevel(stageData.directory);

			defaultCamZoom = stageData.defaultZoom ?? 1;

			stageUI = "normal";
			if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
				stageUI = stageData.stageUI;
			else {
				if (stageData.isPixelStage)
					stageUI = "pixel";
			}

			BF_X = stageData.boyfriend[0];
			BF_Y = stageData.boyfriend[1];
			GF_X = stageData.girlfriend[0];
			GF_Y = stageData.girlfriend[1];
			DAD_X = stageData.opponent[0];
			DAD_Y = stageData.opponent[1];

			if (stageData.camera_speed != null)
				cameraSpeed = stageData.camera_speed;

			boyfriendCameraOffset = stageData.camera_boyfriend;
			if (boyfriendCameraOffset == null) // Fucks sake should have done it since the start :rolling_eyes:
				boyfriendCameraOffset = [0, 0];

			opponentCameraOffset = stageData.camera_opponent;
			if (opponentCameraOffset == null)
				opponentCameraOffset = [0, 0];

			girlfriendCameraOffset = stageData.camera_girlfriend;
			if (girlfriendCameraOffset == null)
				girlfriendCameraOffset = [0, 0];
		});

		#if HSC_ALLOWED
		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;

			Mods.currentModDirectory = stageModDir;

			if (startHScriptsNamed('stages/' + curStage + '.hsc', true))
				stageExists = true;

			Mods.currentModDirectory = oldModDir;
		});
		#end

		preloadTasks.push(() -> {
			if(stageData != null && stageData.preload != null)
			{
				for (asset in Reflect.fields(stageData.preload))
				{
					var filters:Int = Reflect.field(stageData.preload, asset);
					var asset:String = asset.trim();

					if(filters < 0 || StageData.validateVisibility(filters))
					{
						if(asset.startsWith('images/'))
							precacheList.set(asset.substr('images/'.length), 'image');
						else if(asset.startsWith('sounds/'))
							precacheList.set(asset.substr('sounds/'.length), 'sound');
						else if(asset.startsWith('music/'))
							precacheList.set(asset.substr('music/'.length), 'music');
					}
				}
			}

			try {
				var path:String = Paths.json('$songName/preload');
				var json:Dynamic = null;

				#if MODS_ALLOWED
				var moddyFile:String = Paths.modsJson('$songName/preload');
				if (FunkinFileSystem.exists(moddyFile)) json = Json.parse(File.getContent(moddyFile));
				else json = Json.parse(File.getContent(path));
				#else
				json = Json.parse(Assets.getText(path));
				#end

				if(json != null)
				{
					for (asset in Reflect.fields(json))
					{
						var filters:Int = Reflect.field(json, asset);
						var asset:String = asset.trim();

						if(filters < 0 || StageData.validateVisibility(filters))
						{
							if(asset.startsWith('images/'))
								precacheList.set(asset.substr('images/'.length), 'image');
							else if(asset.startsWith('sounds/'))
								precacheList.set(asset.substr('sounds/'.length), 'sound');
							else if(asset.startsWith('music/'))
								precacheList.set(asset.substr('music/'.length), 'music');
						}
					}
				}
			}
			catch(e:Dynamic) {
				trace(e);
			}
		});

		preloadTasks.push(() -> {
			boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
			dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
			gfGroup = new FlxSpriteGroup(GF_X, GF_Y);
		});

		preloadTasks.push(() -> {
			// if (stage3D != null) {
			// 	Main.view3D.removeScene();
			// 	stage3D = null;
			// }

			stage3D = FunkinStage3D.load(stageData);

			trace(stage3D);
			if (stage3D == null)
				return;

			add(stage3D);

			@:privateAccess stage3D.view2.onDebug = (v) -> {
				if (subState != null)
					return;

				forcePause = v;
				if (v)
					pause();
				else
					resume();
			};
		});

		preloadTasks.push(() -> {
			if (stage3D == null) {
				switch (curStage) {
					case 'stage', 'mainStage': new states.stages.StageWeek1(); // Week 1
					case 'stage-erect', 'mainStageErect': new states.stages.StageErect(); // Week 1 (Erect)
					case 'spooky', 'spookyMansion': new states.stages.Spooky(); // Week 2
					case 'spooky-erect', 'spookyMansionErect': new states.stages.SpookyErect(); // Week 2 (Erect)
					case 'philly', 'phillyTrain': new states.stages.Philly(); // Week 3
					case 'philly-erect', 'phillyTrainErect': new states.stages.PhillyErect(); // Week 3 (Erect)
					case 'limo', 'limoRide': new states.stages.Limo(); // Week 4
					case 'limo-erect', 'limoRideErect': new states.stages.LimoErect(); // Week 4 (Erect)
					case 'mall', 'mallXmas': new states.stages.Mall(); // Week 5 - Cocoa, Eggnog
					case 'mall-erect', 'mallXmasErect': new states.stages.MallErect(); // Week 5 (Erect)
					case 'mallEvil': new states.stages.MallEvil(); // Week 5 - Winter Horrorland
					case 'school': new states.stages.School(); // Week 6 - Senpai, Roses
					case 'school-erect', 'schoolErect': new states.stages.SchoolErect(); // Week 6 (Erect) - Senpai, Roses
					case 'schoolEvil', 'schoolEvilErect': new states.stages.SchoolEvil(); // Week 6 - Thorns
					case 'tank', 'tankmanBattlefield': new states.stages.Tank(); // Week 7 - Ugh, Guns, Stress
					case 'tank-erect', 'tankmanBattlefieldErect': new states.stages.FranksSpiritsBowling(); // Week 7 (Erect)
					case 'phillyStreets', 'phillyStreets-erect', 'phillyStreetsErect': new states.stages.PhillyStreets(); // Weekend 1
					case 'phillyBlazin': new states.stages.PhillyBlazin(); // Weekend 1 (Blazin')
				}
			}

			if (stage3D != null || stages.length > 0)
				stageExists = true;

			if (isPixelStage) {
				introSoundsSuffix = '-pixel';
				skinsSuffix = '-pixel';
			}
			
			if (curStage.startsWith('mall')) {
				skinsSuffix = '-christmas';
			}

			if (curStage.startsWith('limo')) {
				skinsSuffix = '-car';
			}

			if(stageData.objects != null && stageData.objects.length > 0)
			{
				var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup, boyfriendGroup, this);
				for (key => spr in list)
					if(!StageData.reservedNames.contains(key))
						modchartSprites.set(key, spr);
			}
			else
			{
				add(gfGroup);
				add(dadGroup);
				add(boyfriendGroup);
			}

			#if LUA_ALLOWED
			luaDebugGroup = new FlxTypedGroup<DebugLuaText>();
			luaDebugGroup.cameras = [camOther];
			add(luaDebugGroup);
			#end
			
			if (ClientPrefs.data.oldCameraSystem)
			{
				camFollow = new FlxPoint();
				camFollowPos = new FlxObject(0, 0, 1, 1);
			}
			else {
				camFollow = new FlxObject(0, 0, 1, 1);
			}
		});

		// "GLOBAL" SCRIPTS
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			// "GLOBAL" SCRIPTS
			findAndStartScripts('codenameScripts', true);
			findAndStartScripts('scripts');
			findAndStartScripts('songs', true); //global scripts for PlayStation
			findAndStartScripts('songs/${songName}/scripts', true);
			/*
			var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'scripts/');
			for (folder in foldersToCheck)
				for (file in FunkinFileSystem.readDirectory(folder))
				{
					if(file.toLowerCase().endsWith('.lua'))
						new FunkinLua(folder + file);
					#if HSCRIPT_ALLOWED
					if(file.toLowerCase().endsWith('.hx'))
						initHScript(folder + file);
					#end
				}
			*/
		});
		#end

		// STAGE SCRIPTS
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;
			
			Mods.currentModDirectory = stageModDir;
			if (startLuasNamed('stages/' + curStage + '.lua'))
				stageExists = true;

			Mods.currentModDirectory = oldModDir;
		});
		#end

		#if HSCRIPT_ALLOWED
		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;

			Mods.currentModDirectory = stageModDir;
			if (startHScriptsNamed('stages/' + curStage + '.hx'))
				stageExists = true;

			Mods.currentModDirectory = oldModDir;
		});
		#end

		function initPlayCharacter(isRight:Bool, ?player:Player, ?sid:String) {
			var char:Character = null;

			oldModDir = Mods.currentModDirectory;

			final songPlayer = (isRight ? SONG.player1 : SONG.player2) ?? '';

			function songPlayerMatchesSkin(skin:String) {
				return songPlayer.startsWith(skin);
			}

			// if online player is defined
			if (player != null) {
				if (player.skin.length > 0 && !songPlayerMatchesSkin(player.skin.items[0])) {
					Mods.currentModDirectory = player.skin.items[3];
					char = new Character(0, 0, player.skin.items[0] + skinsSuffix + player.skin.items[isRight ? 2 : 1], playsAsBF() == isRight, true, isRight ? 'bf' : 'dad');
				}
			}
			// if skin is present for the playable character while offline
			else if (isRight && ClientPrefs.data.currentSkin != null && !songPlayerMatchesSkin(ClientPrefs.data.currentSkin[0])) {
				Mods.currentModDirectory = ClientPrefs.data.currentSkin[3];
				char = new Character(0, 0, ClientPrefs.data.currentSkin[0] + skinsSuffix + ClientPrefs.data.currentSkin[isRight ? 2 : 1], playsAsBF() == isRight, true, isRight ? 'bf' : 'dad');
			}

			// refuse non-blazin characters for blazin
			if (char != null && songPlayer.endsWith('-blazin') && !char.curCharacter.endsWith('-blazin')) {
				char.destroy();
				char = null;
			}

			// when the character has failed to load
			if (char == null || char.loadFailed) {
				trace("fallback to there");
				Mods.currentModDirectory = oldModDir;
				char = new Character(0, 0, songPlayer, isRight, false, isRight ? 'bf' : 'dad');

				// another fallback, if SONG.player1/2 didn't specify the suffix then it is searched and appended
				if (char.loadFailed) {
					for (suffix in (isRight ? online.states.SkinsState.RIGHT_SUFFIX : online.states.SkinsState.LEFT_SUFFIX)) {
						final charExists = Character.getCharacterFile(songPlayer + suffix, null, true) != null;
						if (charExists)
							char = new Character(0, 0, songPlayer + suffix, playsAsBF() == isRight, false, isRight ? 'bf' : 'dad');
					}
				}
			}
			
			char.ox = player?.ox ?? 0;
			if (isRight) {
				if (boyfriend == null || char.ox == 0)
					boyfriend = char;
				var icon = new HealthIcon(char.healthIcon, true);
				icon.ox = char.ox;
				if (iconP1 == null)
					iconP1 = icon;
				char.gameIconIndex = iconP1s.length;
				iconP1s.push(icon);
			}
			else {
				if (dad == null || char.ox == 0)
					dad = char;
				var icon = new HealthIcon(char.healthIcon, false);
				icon.ox = char.ox;
				if (iconP2 == null)
					iconP2 = icon;
				char.gameIconIndex = iconP2s.length;
				iconP2s.push(icon);
			}

			if (stage == null) startCharacterPos(char, !isRight);
			(isRight ? boyfriendGroup : dadGroup).add(char);
			startCharacterScripts(char.curCharacter, sid, isRight);

			Mods.currentModDirectory = oldModDir;

			if (stage != null) stage.applyCharStuff(char, isRight ? "boyfriend" : "dad", 0);

			return char;
		}

		preloadTasks.push(() -> {
			//init characters
			if (GameClient.isConnected()) {
				for (sid => player in GameClient.room.state.players) {
					var char = initPlayCharacter(player.bfSide, player, sid);

					//renewed character system
					var strumIndex:Int = player.bfSide ? 1 : 0;
					if (!onlineStrumlines.exists(sid))
						onlineStrumlines.set(sid, new Map<Int, Array<Character>>());

					var sidMap = onlineStrumlines.get(sid);
					if (sidMap.exists(strumIndex))
						sidMap.get(strumIndex).push(char);
					else
						sidMap.set(strumIndex, [char]);

					var nameplate = new FlxText();
					nameplate.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 30 : 25, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					nameplate.borderSize = 1.5;
					nameplate.cameras = char.cameras;
					nameplate.text = player.name;
					nameplate.x = char.x + char.width / 2 - nameplate.width / 2;
					nameplate.y = char.y - nameplate.height - 20;
					nameplate.visible = ClientPrefs.data.nameplateFadeTime != 0;
					nameplates.add(nameplate);
				}

				playOtherSide = (dad == null || boyfriend == null);
			}

			if (dad == null) {
				initPlayCharacter(false);
				isNulledDad = true;
				if (GameClient.isConnected() && GameClient.room.state.royalMode) {
					dad.visible = false;
				}
			}

			if (boyfriend == null) {
				initPlayCharacter(true);
				isNulledBf = true;
				if (GameClient.isConnected() && GameClient.room.state.royalMode) {
					boyfriend.visible = false;
				}
			}

			dummy = new Character(0, 0);

			function sortByOX(a:FlxSprite, b:FlxSprite) {
				if (!(a is Character) || !(b is Character))
					return -1;

				return cast(b, Character).ox - cast(a, Character).ox;
			}
			boyfriendGroup.members.sort(sortByOX);
			dadGroup.members.sort(sortByOX);

			function sortIconByOX(a:HealthIcon, b:HealthIcon) {
				return b.ox - a.ox;
			}
			iconP1s.sort(sortIconByOX);
			iconP2s.sort(sortIconByOX);
		});

		// NOTE: in regular psych girlfriend is initialized before other characters (hopefully this doesn't cause issues with mods)
		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;

			if (!stageData.hide_girlfriend) {
				var gfName = SONG.gfVersion;

				if (boyfriend.isSkin && boyfriend.speakerName != null 
				&& !SONG.player1.startsWith(boyfriend.curCharacter) && !SONG.gfVersion.startsWith(boyfriend.speakerName)) {
					gfName = boyfriend.speakerName;
					Mods.currentModDirectory = boyfriend.modDir;
				}

				if (gfName == null || gfName.trim().length < 1) {
					gfName = 'gf' + skinsSuffix;
				}

				gf = new Character(0, 0, gfName, false, false, 'gf');
				gf.loadSpeaker();
				if (gf?.speaker != null) {
					/* if (gf.speaker.codenameOffsets) add(gf.speaker);
					else */ gfGroup.add(gf.speaker);

					if (gf.speaker is Character) {
						if (stage == null) startCharacterPos(cast gf.speaker);
						if (stage != null) stage.applyCharStuff(cast gf.speaker, "girlfriend", 0);
					}
				}
				if (stage == null) startCharacterPos(gf);
				if (stage != null) stage.applyCharStuff(gf, "girlfriend", 0);

				//looks fuckin ugly, why is it there from old fnf vanilla to psych lolol
				// gfGroup.scrollFactor.set(0.95, 0.95);
				if (gf.codenameOffsets) add(gf);
				else gfGroup.add(gf);

				startCharacterScripts(gf.curCharacter);
			}

			if (gf != null && GameClient.isConnected() && GameClient.room.state.hideGF) {
				for (item in gfGroup) {
					if (item == null)
						continue;

					item.visible = false;
				}
			}

			Mods.currentModDirectory = oldModDir;
		});

		preloadTasks.push(() -> {
			camPos = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
			if (gf != null) {
				camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
				camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
			}

			if (dad.curCharacter.startsWith('gf') && Paths.formatToSongPath(SONG.song) == 'tutorial') {
				dad.setPosition(GF_X, GF_Y);
				if (gf != null)
					gf.visible = false;
			}
		});

		preloadTasks.push(() -> {
			comboGroup = new FlxSpriteGroup();
			add(comboGroup);
			noteGroup = new FlxTypedGroup<FlxBasic>();
			add(noteGroup);
			uiGroup = new FlxSpriteGroup();
			add(uiGroup);

			uiGroup.cameras = [camHUD];
			noteGroup.cameras = [camHUD];
			comboGroup.cameras = [camHUD];

			noteGroup.add(strumLines);

			//Null Object Fix
			if (replayPlayer == null && ClientPrefs.data.noteUnderlayOpacity > 0) {
				noteUnderlays = new FlxTypedGroup<FlxSprite>();
				noteGroup.add(noteUnderlays);
			}

			#if HSC_ALLOWED
			scripts.set("SONG", SONG);
			scripts.setupPlayState();
			scripts.load();
			#end

			//maybe this can fix all problems lol
			var event = EventManager.get(AmountEvent).recycle(4);
			if (!scripts.event("onPreGenerateStrums", event).cancelled) {
				//Softcoded Extra Strumlines
				if (SONG.strumLines != null && SONG.strumLines != []) {
					for (strumIndex => strumData in SONG.strumLines) {
						var chars:Array<Character> = [];
						if (GameClient.isConnected()) {
							for (sid => player in GameClient.room.state.players) {
								if (strumData.characters != null && strumData.characters != [] && strumIndex >= 3) {
									for (char in strumData.characters) {
										if (player.bfSide && !strumData.cpu || !player.bfSide && strumData.cpu) {
											var char = initStrumLineCharacter(0, 0, char, !strumData.cpu, strumData.type, sid, strumIndex);
											if (sid == GameClient.room.sessionId)
												chars.push(char);
										}
									}
								}
							}
							//hardcoded because I don't have enough time to do online char stuff.
							switch(strumIndex) {
								case 0: chars.push(getOnlineChar(GameClient.room.sessionId, false));
								case 1: chars.push(getOnlineChar(GameClient.room.sessionId, true));
								case 2: chars.push(gf);
							}						
							var strum = createStrum(strumData.cpu, chars, strumData.visible);
						} else {
							if (strumData.characters != null && strumData.characters != [] && strumIndex >= 3) {
								for (char in strumData.characters) {
									chars.push(initStrumLineCharacter(0, 0, char, !strumData.cpu, strumData.type));
								}
							}
							//hardcoded because I don't have enough time to do online char stuff.
							switch(strumIndex) {
								case 0: chars.push(dad);
								case 1: chars.push(boyfriend);
								case 2: chars.push(gf);
							}						
							var strum = createStrum(strumData.cpu, chars, strumData.visible);
						}
					}
				} else {
					createStrum(true, [dad], true);
					createStrum(false, [boyfriend], true);
					createStrum(true, [gf], false);
				}
				scripts.event("onPostGenerateStrums", event);
			}
		});

		var event = EventManager.get(AmountEvent).recycle(4);
		if (!scripts.event("onPreGenerateStrums", event).cancelled) {
			// Softcoded Extra Strumlines
			if (SONG.strumLines != null && SONG.strumLines != []) {
				for (strumIndex => strumData in SONG.strumLines) {
					var chars:Array<Character> = [];
					
					// 1. Handle dynamic online characters for hardcoded strumlines (0 and 1)
					if (GameClient.isConnected()) {
						for (sid => player in GameClient.room.state.players) {
							if (characters.exists(sid)) {
								// If it's the Opponent Strumline (0) and player is NOT on bfSide
								if (strumIndex == 0 && !player.bfSide) {
									chars.push(characters.get(sid));
								}
								// If it's the Player Strumline (1) and player IS on bfSide
								else if (strumIndex == 1 && player.bfSide) {
									chars.push(characters.get(sid));
								}
							}
						}
					}

					// 2. Fallback to default characters if online list is empty or for GF/Extra lines
					if (chars.length == 0) {
						switch(strumIndex) {
							case 0: chars.push(dad);
							case 1: chars.push(boyfriend);
							case 2: if (gf != null) chars.push(gf);
						}
					}

					// 3. Handle Softcoded Extra Strumlines (Index 3+)
					if (strumData.characters != null && strumData.characters != [] && strumIndex >= 3) {
						for (char in strumData.characters) {
							chars.push(initStrumLineCharacter(0, 0, char, !strumData.cpu, strumData.type));
						}
					}
					
					var strum = createStrum(strumData.cpu, chars, strumData.visible);
					
					// 4. Apply stage positioning to ALL characters in the array
					if (stage != null) {
						for (i in 0...chars.length) {
							var charType = (strumIndex == 0) ? "dad" : (strumIndex == 1 ? "boyfriend" : "girlfriend");
							stage.applyCharStuff(chars[i], charType, 0);
							
							// Offset extra players so they don't Z-fight/overlap perfectly
							if (i > 0) {
								chars[i].x += (strumIndex == 0 ? -200 : 200) * i; 
							}
						}
					}
				}
			} else {
				// Default fallback logic
				createStrum(true, [dad], true);
				createStrum(false, [boyfriend], true);
				if (gf != null) createStrum(true, [gf], false);
			}
			scripts.event("onPostGenerateStrums", event);
		}

		preloadTasks.push(() -> {
			Conductor.songPosition = -5000 / Conductor.songPosition;
			showTime = (ClientPrefs.data.timeBarType != 'Disabled');
			timeTxt = new FlxText(0, 10, FlxG.width, "", 32);
			timeTxt.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 32 : 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			timeTxt.scrollFactor.set();
			timeTxt.alpha = 0;
			timeTxt.borderSize = 2;
			timeTxt.visible = updateTime = showTime;
			if(ClientPrefs.data.downScroll) timeTxt.y = FlxG.height - 44;
			if(ClientPrefs.data.timeBarType == 'Song Name') timeTxt.text = SONG.song;
		});

		preloadTasks.push(() -> {
			timeBar = new HealthBar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
			timeBar.scrollFactor.set();
			timeBar.screenCenter(X);
			timeBar.alpha = 0;
			timeBar.visible = showTime;
			uiGroup.add(timeBar);
			uiGroup.add(timeTxt);
		});

		preloadTasks.push(() -> {
			strumLineNotes = new StrumLine();

			noteGroup.add(strumLineNotes);

			generateSong(SONG.song);

			noteGroup.add(grpHoldSplashes);
			noteGroup.add(grpNoteSplashes);

			keysArray = getKeysArray(Note.maniaKeys);

			for (key in keysArray) {
				// for (bind in controls.keyboardBinds['taunt']) {
					if (controls.keyboardBinds[key] != null && controls.keyboardBinds[key].contains(FlxKey.SPACE)) {
						canSpaceTaunt = false;
					}
				// }
			}
		});

		preloadTasks.push(() -> {
			var splash:NoteSplash = new NoteSplash(100, 100);
			grpNoteSplashes.add(splash);
			splash.alpha = 0.0001; //cant make it invisible or it won't allow precaching

			SustainSplash.startCrochet = Conductor.stepCrochet;
			SustainSplash.frameRate = Math.floor(24 / 100 * SONG.bpm);
			var splash:SustainSplash = new SustainSplash();
			grpHoldSplashes.add(splash);
			splash.visible = true;
			splash.alpha = 0.0001;
			#if HSC_ALLOWED
			scripts.call("create");
			#end
		});

		preloadTasks.push(() -> {
			if (ClientPrefs.data.oldCameraSystem)
			{
				snapCamFollowToPos(camPos.x, camPos.y);
				if (prevCamFollow != null)
				{
					camFollow = prevCamFollow;
					prevCamFollow = null;
				}

				if (prevCamFollowPos != null)
				{
					camFollowPos = prevCamFollowPos;
					prevCamFollowPos = null;
				}
				add(camFollowPos);

				FlxG.camera.follow(camFollowPos, LOCKON, 1);
			}
			else
			{
				camFollow.setPosition(camPos.x, camPos.y);
				camPos.put();
				if (prevCamFollow != null)
				{
					camFollow = prevCamFollow;
					prevCamFollow = null;
				}

				add(camFollow);

				FlxG.camera.follow(camFollow, LOCKON, 0);
			}

			FlxG.camera.zoom = defaultCamZoom; //I'm gonna find and kill the person who added this.
			if (ClientPrefs.data.oldCameraSystem)
				FlxG.camera.focusOn(camFollow);
			else
				FlxG.camera.snapToTarget();

			if (ClientPrefs.data.oldCameraSystem)
				FlxG.fixedTimestep = false;

			FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
			moveCameraSection();
		});

		preloadTasks.push(() -> {
			healthBar = new HealthBar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
			healthBar.screenCenter(X);
			healthBar.leftToRight = false;
			healthBar.scrollFactor.set();
			healthBar.visible = !ClientPrefs.data.hideHud;
			healthBar.alpha = ClientPrefs.data.healthBarAlpha;
			reloadHealthBarColors();
			uiGroup.add(healthBar);

			for (icon in iconP1s.concat(iconP2s)) {
				icon.visible = !ClientPrefs.data.hideHud;
				icon.alpha = ClientPrefs.data.healthBarAlpha;
				uiGroup.add(icon);
			}
		});

		preloadTasks.push(() -> {
			scoreTxtOriginY = ClientPrefs.data.downScroll ? 120 : 700;
			
			scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
			scoreTxt.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 20 : 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			scoreTxt.scrollFactor.set();
			scoreTxt.borderSize = 1.25;
			scoreTxt.visible = !ClientPrefs.data.hideHud;
			uiGroup.add(scoreTxt);
		});

		if (GameClient.isConnected()) {
			preloadTasks.push(() -> {
				scoreTxt.visible = false;

				function createText(isRight:Bool, ?ox:Int = 0, ?isOnline:Bool = false) {
					var scoreTxtPlayer = new FlxText(0, 0, FlxG.width, "", 20);
					scoreTxtPlayer.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', (!isPixelStage ? 18 : 16) - (isOnline ? -4 : 0), FlxColor.WHITE, isRight ? RIGHT : LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					scoreTxtPlayer.scrollFactor.set();
					scoreTxtPlayer.borderSize = 1.25;
					scoreTxtPlayer.visible = !ClientPrefs.data.hideHud;
					scoreTxtPlayer.camera = camOther;
					uiGroup.add(scoreTxtPlayer);
					
					scoreTxtPlayer.y = scoreTxtOriginY - (ox * 20) - scoreTxtPlayer.height;
	
					if (isRight)
						scoreTxtPlayer.offset.x += 30;
					else
						scoreTxtPlayer.offset.x -= 30;

					if (!isRight && scoreTxtP1 == null)
						scoreTxtP1 = scoreTxtPlayer;

					if (isRight && scoreTxtP2 == null)
						scoreTxtP2 = scoreTxtPlayer;

					return scoreTxtPlayer;
				}

				if (GameClient.room.state.teamMode) {
					scoreTxtOthers.set('LEFTSIDE', createText(false));
					scoreTxtOthers.set('RIGHTSIDE', createText(true));

					scoreTxtOthers.get(getPlayerStats(GameClient.room.sessionId).player.bfSide ? 'RIGHTSIDE' : 'LEFTSIDE').color = FlxColor.YELLOW;
				}
				else {
					for (sid => player in GameClient.room.state.players) {
						scoreTxtOthers.set(sid, createText(player.bfSide, player.ox, true));
					}
					scoreTxtOthers.get(GameClient.room.sessionId).color = FlxColor.YELLOW;
				}
			});
		}

		preloadTasks.push(() -> {
			botplayTxt = new FlxText(0, timeBar.y + 55, 0, "BOTPLAY", 32);
			botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			botplayTxt.scrollFactor.set();
			botplayTxt.borderSize = 1.25;
			showBotplay();
			uiGroup.add(botplayTxt);
			if (ClientPrefs.data.downScroll) {
				botplayTxt.y = timeBar.y - 78;
			}

			startingSong = true;
		});
		
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			for (notetype in noteTypes)
				startLuasNamed('custom_notetypes/' + notetype + '.lua');
		});

		preloadTasks.push(() -> {
			for (event in eventsPushed)
				startLuasNamed('custom_events/' + event + '.lua');
		});
		#end

		#if HSCRIPT_ALLOWED
		preloadTasks.push(() -> {
			for (notetype in noteTypes)
				startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		});

		preloadTasks.push(() -> {
			for (event in eventsPushed)
				startHScriptsNamed('custom_events/' + event + '.hx');
		});
		#end
		
		#if HSC_ALLOWED
		preloadTasks.push(() -> {
			for (notetype in noteTypes)
				startHScriptsNamed('custom_notetypes/' + notetype + '.hsc', true);
		});

		preloadTasks.push(() -> {
			for (event in eventsPushed)
				startHScriptsNamed('custom_events/' + event + '.hsc', true);
		});
		#end

		preloadTasks.push(() -> {
			noteTypes = null;
			eventsPushed = null;

			if(eventNotes.length > 1)
			{
				for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
				eventNotes.sort(sortByTime);
			}
		});

		// SONG SPECIFIC SCRIPTS
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			findAndStartScripts('data/${songName}');
		});
		#end
		
		#if HSC_ALLOWED
		preloadTasks.push(() -> {
			introAssets.set('default', [null, 'ready', 'set', 'go']);
			introAssets.set('pixel', [null, 'pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel']);
		});
		#end

		if (GameClient.isConnected()) {
			preloadTasks.push(() -> {
				waitReadySpr = new Alphabet(0, 0, controls.mobileControls ? Language.getText("TOUCH YOUR SCREEN TO START") : Language.getText("PRESS ACCEPT TO START"), true);
				waitReadySpr.cameras = [camOther];
				waitReadySpr.alignment = CENTERED;
				waitReadySpr.x = FlxG.width / 2;
				waitReadySpr.screenCenter(Y);
			});
		}

		preloadTasks.push(() -> {
			updateScoreSelf();
			// RecalculateRating();
			// if (GameClient.isConnected())
			// 	RecalculateRatingOpponent();
		});

		preloadTasks.push(() -> {
			//PRECACHING MISS SOUNDS BECAUSE I THINK THEY CAN LAG PEOPLE AND FUCK THEM UP IDK HOW HAXE WORKS
			if(ClientPrefs.data.hitsoundVolume > 0) precacheList.set('hitsound', 'sound');
			precacheList.set('missnote1', 'sound');
			precacheList.set('missnote2', 'sound');
			precacheList.set('missnote3', 'sound');

			if (PauseSubState.songName != null) {
				precacheList.set(PauseSubState.songName, 'music');
			} else if(ClientPrefs.data.pauseMusic != 'None') {
				precacheList.set(Paths.formatToSongPath(ClientPrefs.data.pauseMusic), 'music');
			}

			precacheList.set('alphabet', 'image');
			resetRPC();
		});

		preloadTasks.push(() -> {
			#if LUA_ALLOWED
			for (_ in modchartSprites) {
				stageExists = true;
				break;
			}
			#end

			if (!stageExists) {
				Sys.println("STAGE IS EMPTY");
				var prevLevel = Paths.currentLevel;
				Paths.setCurrentLevel("week1");
				//new online.OnlineStage();
				Paths.setCurrentLevel(prevLevel);
			}
		});

		preloadTasks.push(() -> {
			cacheCountdown();
			cachePopUpScore();
			
			for (folderOrFile => type in precacheList)
			{
				final ext = switch (type) {
					case 'image':
						'.png';
					case 'sound':
						'.${Paths.SOUND_EXT}';
					case 'music':
						'.${Paths.SOUND_EXT}';
					default:
						null;
				};
				final prefix = switch (type) {
					case 'image':
						'images';
					case 'sound':
						'sounds';
					case 'music':
						'music';
					default:
						null;
				};
				final assetType:openfl.utils.AssetType = switch (type) {
					case 'image':
						IMAGE;
					case 'sound', 'music':
						SOUND;
					default:
						null;
				};
				var keys = [];

				var nam:String = folderOrFile.trim();
				if(nam.endsWith('/')) {
					for (subfolder in Mods.directoriesWithFile(Paths.getSharedPath(), '$prefix/$nam'))
					{
						for (file in FunkinFileSystem.readDirectory(subfolder))
						{
							if(file.endsWith(ext))
							{
								var toAdd:String = nam + haxe.io.Path.withoutExtension(file);
								if(!keys.contains(toAdd)) keys.push(toAdd);
							}
						}
					}

					//trace('Folder detected! ' + folder);
				}
				else {
					keys.push(nam);
				}

				var i:Int = 0;
				while(i < keys.length)
				{
					var member:String = keys[i];
					var myKey = '$prefix/$member$ext';

					//trace('attempting on $prefix: $myKey');
					var doTrace:Bool = false;
					if(member.endsWith('/') || (!Paths.fileExists(myKey, assetType, false) && (doTrace = true)))
					{
						keys.remove(member);
						if(doTrace) trace('Removed invalid $prefix: $member');
					}
					else i++;
				}

				for (key in keys) {
					switch(type)
					{
						case 'image':
							Paths.image(key);
						case 'sound':
							Paths.sound(key);
						case 'music':
							Paths.music(key);
					}
				}
			}
		});

		if (GameClient.isConnected()) {
			preloadTasks.push(() -> {
				add(chatBox = new ChatBox(camOther, 100));
				// add(leavePie = new LeavePie());
				// leavePie.cameras = [camOther];
			});
		}

		preloadTasks.push(() -> {
			if (replayData != null && !GameClient.isConnected()) {
				add(replayPlayer = new ReplayPlayer(this, replayData));
			}
			else {
				FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
				FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

				if (!ClientPrefs.data.disableReplays && !isInvalidScore() && !chartingMode) {
					add(replayRecorder = new ReplayRecorder(this));
				}
			}

			if (!ClientPrefs.data.disableSongComments && (replayPlayer != null || cpuControlled || ClientPrefs.data.midSongCommentsOpacity > 0.0) && songId != null) {
				nicomments = new NicommentsView(songId);
				nicomments.cameras = [camOther];
				if (replayPlayer == null && ClientPrefs.data.midSongCommentsOpacity > 0.0) {
					nicomments.cameras = [camGame];
					nicomments.alpha = ClientPrefs.data.midSongCommentsOpacity;
					nicomments.offsetY = !ClientPrefs.data.downScroll ? 150 : 0;
				}
				add(nicomments);
			}

			// may crash???
			// Paths.clearUnusedMemory();

			CustomFadeTransition.nextCamera = camOther;
			if (eventNotes.length < 1)
				checkEventNote();

			if (GameClient.isConnected())
				generateStrums();

			setOnScripts('isDuel', isDuel);
			setOnScripts('duoOpponentSID', duoOpponentSID);

			mobileManager.addMobilePad((replayData != null || cpuControlled) ? 'LEFT_RIGHT' : 'NONE',
										(GameClient.isConnected()) ? 'P_C_T' : (replayData != null || cpuControlled) ? 'P_X_Y' : 'P_T');
			mobileManager.addMobilePadCamera();
			addPlayStateHitbox(null, true);
		});

		var loaderGroup = new online.objects.LoadingSprite(preloadTasks.length, camLoading);
		add(loaderGroup);
		
		// var i = 0;
		asyncLoop = new FlxAsyncLoop(preloadTasks.length, () -> {
			preloadTasks.shift()();
			// trace(i++, Math.abs(FlxMath.roundDecimal(openfl.system.System.totalMemory / 1000000, 1)));

			loaderGroup.addProgress(preloadTasks.length);

			if (preloadTasks.length <= 0) {
				isCreated = true;

				FlxTween.tween(camLoading, {alpha: 0}, 0.5, {ease: FlxEase.circOut, onComplete: t -> {
					loaderGroup.killMembers();
					FlxG.cameras.remove(camLoading, true);
				}});

				if (redditMod) {
					online.util.FileUtils.removeFiles(haxe.io.Path.join([Paths.mods(), 'reddit']));
				}

				// now that the game has loaded we can let the game update() itself properly
				theWorld = false;

				startCallback();
				stagesFunc(function(stage:BaseStage) stage.createPost());
				callOnScripts('onCreatePost');
				__updateNote_event = EventManager.get(NoteUpdateEvent);
				registerMessages();

				add(nameplates);
				if (ClientPrefs.data.nameplateFadeTime > 0) {
					for (nameplate in nameplates) {
						new FlxTimer().start(ClientPrefs.data.nameplateFadeTime, function(tmr:FlxTimer) {
							FlxTween.tween(nameplate, {alpha: 0}, 1);
						});
					}
				}

				if (ClientPrefs.isDebug()) {
					debugPoser = new online.objects.DebugPosHelper();
					debugPoser.cameras = [camOther];
					add(debugPoser);
				}
			}
		}, 1);
		loaderGroup.add(asyncLoop);

		orderOffset = 2;

		super.create();

		Paths.clearUnusedMemory();
	}

	public function snapCamFollowToPos(x:Float, y:Float) {
		if (ClientPrefs.data.oldCameraSystem)
		{
			camFollow.set(x, y);
			camFollowPos.setPosition(x, y);
		}
	}

	/**
	 * Gets the array of characters for a specific player's side.
	 * @param sid The session ID of the player.
	 * @param isBF Whether to get the BF side (true) or Dad side (0).
	 */
	public function getOnlineCharacters(sid:String, isBF:Bool):Array<Character> {
		var strumIndex:Int = isBF ? 1 : 0;
		
		if (onlineStrumlines.exists(sid)) {
			var sidMap = onlineStrumlines.get(sid);
			if (sidMap.exists(strumIndex)) {
				return sidMap.get(strumIndex);
			}
		}
		return []; // Return empty array if not found
	}

	/**
	 * Gets the first/main character for a player's side.
	 */
	public function getOnlineChar(sid:String, isBF:Bool):Character {
		var chars = getOnlineCharacters(sid, isBF);
		return (chars.length > 0) ? chars[0] : null;
	}

	var debugPoser:online.objects.DebugPosHelper;

	@:unreflective public var botplayVisibility = false;
	function showBotplay() {
		if (botplayTxt == null)
			return;

		var pos = 0;
		
		botplayVisibility = cpuControlled;

		// if (GameClient.isConnected()) {
		// 	if (GameClient.room.state.player1.botplay && GameClient.room.state.player2.botplay)
		// 		pos = 0;
		// 	else if (GameClient.room.state.player1.botplay)
		// 		pos = (GameClient.room.state.swagSides ? 2 : 1);
		// 	else if (GameClient.room.state.player2.botplay)
		// 		pos = (GameClient.room.state.swagSides ? 1 : 2);
		// 	else
		// 		pos = -1;

		// 	botplayVisibility = pos != -1;
		// }

		botplayTxt.x = FlxG.width / 2 - botplayTxt.width / 2;

		switch (pos) {
			case 1:
				botplayTxt.x -= 320;
			case 2:
				botplayTxt.x += 320;
		}

		botplayTxt.visible = botplayVisibility;
	}

	function realignLoadCam(cam:FlxCamera) {
		if (cam == camLoading || !FlxG.cameras.list.contains(camLoading))
			return;

		FlxG.cameras.remove(camLoading, false);
		FlxG.cameras.add(camLoading, false);
		FlxG.cameras.cameraAdded.addOnce(realignLoadCam);
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		#else 
		value = 1;
		#end

		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.safeZoneOffset = (ClientPrefs.getSafeFrames() / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if(videoCutscene != null && videoCutscene.videoSprite != null) videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		return value;
	}

	public function addTextToDebug(text:String, color:FlxColor) {
		if (!ClientPrefs.isDebug()) {
			return;
		}

		#if LUA_ALLOWED
		var newText:DebugLuaText = luaDebugGroup.recycle(DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);
		#end
	}

	public function reloadHealthBarColors() {
		if (!isDuel) {
			healthBar.setColors(FlxColor.RED, FlxColor.LIME);
			return;
		}

		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	//Universal character change function for extra chars (used on Errorians first)
	public function changeCharacter(ogCharacter:Character, newCharacter:String, type:String) {
		if (ogCharacter == null || ogCharacter.curCharacter == newCharacter) 
			return;

		switch(type.toLowerCase().trim()) {
			case 'bf' | 'boyfriend' | '0':
				//if (!ClientPrefs.data.modchartSkinChanges && ogCharacter.isSkin) return;

				if (!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character;
					if (ogCharacter.isSkin && newCharacter == SONG.player1) {
						newBoyfriend = ogCharacter;
					} else {
						newBoyfriend = new Character(0, 0, newCharacter, ogCharacter.isPlayer, false, 'bf');
						newBoyfriend.ox = ogCharacter.ox;
						newBoyfriend.gameIconIndex = ogCharacter.gameIconIndex;

						if (!ogCharacter.isPlayer) {
							newBoyfriend.flipX = !newBoyfriend.flipX;
						}

						if (newBoyfriend.codenameOffsets) add(newBoyfriend);
						else boyfriendGroup.add(newBoyfriend);
						if (stage == null) startCharacterPos(newBoyfriend);
						if (stage != null) stage.applyCharStuff(newBoyfriend, "boyfriend", 0);
						newBoyfriend.alpha = 0.00001;
						startCharacterScripts(newBoyfriend.curCharacter, true);
					}
					boyfriendMap.set(newCharacter, newBoyfriend);
				}

				var lastAlpha:Float = ogCharacter.alpha;
				ogCharacter.alpha = 0.00001;

				var newlySpawned = boyfriendMap.get(newCharacter);

				if (ogCharacter == boyfriend) {
					boyfriend = newlySpawned;
					setOnScripts('boyfriendName', boyfriend.curCharacter);
				}

				newlySpawned.alpha = lastAlpha;
				if (iconP1s[newlySpawned.gameIconIndex] != null) {
					iconP1s[newlySpawned.gameIconIndex].changeIcon(newlySpawned.healthIcon);
				}

			case 'dad' | 'opponent' | '1':
				//if (!ClientPrefs.data.modchartSkinChanges && ogCharacter.isSkin) return;

				// --- 1. Cache if it doesn't exist ---
				if (!dadMap.exists(newCharacter)) {
					var newDad:Character;
					if (ogCharacter.isSkin && newCharacter == SONG.player2) {
						newDad = ogCharacter;
					} else {
						newDad = new Character(0, 0, newCharacter, ogCharacter.isPlayer, false, 'dad');
						newDad.ox = ogCharacter.ox;
						newDad.gameIconIndex = ogCharacter.gameIconIndex;

						if (!ogCharacter.isPlayer) {
							newDad.flipX = !newDad.flipX;
						}

						if (newDad.codenameOffsets) add(newDad);
						else dadGroup.add(newDad);
						if (stage == null) startCharacterPos(newDad, true);
						if (stage != null) stage.applyCharStuff(newDad, "dad", 0);
						newDad.alpha = 0.00001;
						startCharacterScripts(newDad.curCharacter, false);
					}
					dadMap.set(newCharacter, newDad);
				}

				var wasGf:Bool = ogCharacter.curCharacter.startsWith('gf-') || ogCharacter.curCharacter == 'gf';
				var lastAlpha:Float = ogCharacter.alpha;
				ogCharacter.alpha = 0.00001;

				var newlySpawned = dadMap.get(newCharacter);

				if (ogCharacter == dad) {
					dad = newlySpawned;
					setOnScripts('dadName', dad.curCharacter);
				}

				if (!newlySpawned.curCharacter.startsWith('gf-') && newlySpawned.curCharacter != 'gf') {
					if (wasGf && gf != null) gf.visible = true;
				} else if (gf != null) {
					gf.visible = false;
				}

				newlySpawned.alpha = lastAlpha;
				if (iconP2s[newlySpawned.gameIconIndex] != null) {
					iconP2s[newlySpawned.gameIconIndex].changeIcon(newlySpawned.healthIcon);
				}

			case 'gf' | 'girlfriend' | '2':
				if (!gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					gfMap.set(newCharacter, newGf);
					if (newGf.codenameOffsets) add(newGf);
					else gfGroup.add(newGf);
					if (stage == null) startCharacterPos(newGf);
					if (stage != null) stage.applyCharStuff(newGf, "girlfriend", 0);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}

				var lastAlpha:Float = ogCharacter.alpha;
				ogCharacter.alpha = 0.00001;
				var newlySpawned = gfMap.get(newCharacter);
				newlySpawned.alpha = lastAlpha;

				if (ogCharacter == gf) {
					gf = newlySpawned;
					setOnScripts('gfName', gf.curCharacter);
				}
		}

		reloadHealthBarColors();
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				function addBoyfriend(character:Character, ?sid:String) {
					if (character != null) {
						if (character.isPlayer != boyfriend.isPlayer)
							return;
						
						if (!ClientPrefs.data.modchartSkinChanges && character.isSkin)
							return;
					}

					var charID = newCharacter + (sid != null ? '__' + sid : '');
					if (!boyfriendMap.exists(charID)) {
						var newBoyfriend:Character;
						if (character?.isSkin && newCharacter == SONG.player1)
							newBoyfriend = character;
						else {
							newBoyfriend = new Character(0, 0, newCharacter, true, false, 'bf');
							newBoyfriend.ox = character?.ox ?? 0;
							newBoyfriend.gameIconIndex = character?.gameIconIndex ?? 0;
							if (newBoyfriend.codenameOffsets) add(newBoyfriend);
							else boyfriendGroup.add(newBoyfriend);
							if (stage == null) startCharacterPos(newBoyfriend);
							if (stage != null) stage.applyCharStuff(newBoyfriend, "boyfriend", 0);
							newBoyfriend.alpha = 0.00001;
							startCharacterScripts(newBoyfriend.curCharacter, sid, true);
						}
						boyfriendMap.set(charID, newBoyfriend);
					}
				}

				addBoyfriend(boyfriend);
				for (sid => sidMap in onlineStrumlines) {
					for (strumIndex => chars in sidMap) {
						for (index => character in chars)
						{
							if (index == 0 || index == 1)
								addBoyfriend(character, sid);
						}
					}
				}
				/* old stuff
				for (sid => character in characters) {
					addBoyfriend(character, sid);
				}
				*/

			case 1:
				function addDad(character:Character, ?sid:String) {
					if (character != null) {
						if (character.isPlayer != dad.isPlayer)
							return;
						
						if (!ClientPrefs.data.modchartSkinChanges && character.isSkin)
							return;
					}

					var charID = newCharacter + (sid != null ? '__' + sid : '');
					if(!dadMap.exists(charID)) {
						var newDad:Character;
						if (character?.isSkin && newCharacter == SONG.player2)
							newDad = character;
						else {
							newDad = new Character(0, 0, newCharacter, !playsAsBF(), false, 'dad');
							newDad.ox = character?.ox ?? 0;
							newDad.gameIconIndex = character?.gameIconIndex ?? 0;
							if (!playsAsBF()) {
								newDad.flipX = !newDad.flipX;
							}
							if (newDad.codenameOffsets) add(newDad);
							else dadGroup.add(newDad);
							if (stage == null) startCharacterPos(newDad, true);
							if (stage != null) stage.applyCharStuff(newDad, "dad", 0);
							newDad.alpha = 0.00001;
							startCharacterScripts(newDad.curCharacter, sid, false);
						}
						dadMap.set(charID, newDad);
					}
				}

				addDad(dad);
				for (sid => sidMap in onlineStrumlines) {
					for (strumIndex => chars in sidMap) {
						for (index => character in chars)
						{
							if (index == 0 || index == 1)
								addDad(character, sid);
						}
					}
				}
				/*
				for (sid => character in characters) {
					addDad(character, sid);
				}
				*/

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					// newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					if (newGf.codenameOffsets) add(newGf);
					else gfGroup.add(newGf);
					if (stage == null) startCharacterPos(newGf);
					if (stage != null) stage.applyCharStuff(newGf, "girlfriend", 0);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String, ?sid:String = null, ?isBF:Null<Bool> = null, ?forcePush:Bool = false)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/' + name + '.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FunkinFileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getPreloadPath(luaFile);
			if(FunkinFileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getPreloadPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			if (!forcePush)
				for (script in luaArray)
				{
					if(script.scriptName == luaFile)
					{
						doPush = false;
						break;
					}
				}
			if(doPush) {
				var lua = new FunkinLua(luaFile);
				lua.set('charTag', getCharPlayTag(isBF, sid));
			}
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FunkinFileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		{
			scriptFile = Paths.getPreloadPath(scriptFile);
			if(FunkinFileSystem.exists(scriptFile))
				doPush = true;
		}
		
		if(doPush)
		{
			if (!forcePush)
				if(SScript.global.exists(scriptFile))
					doPush = false;

			if(doPush) { 
				var hscript = initHScript(scriptFile);
				if (hscript != null) {
					hscript.set('charTag', getCharPlayTag(isBF, sid));
				}
			}
		}
		#end
	}

	function getCharPlayTag(isBF:Null<Bool>, ?sid:String) {
		if (sid != null) {
			return 'characters[${sid}]';
		}
		else {
			if (isBF == null) {
				return 'gf';
			}
			else {
				if (isBF)
					return 'boyfriend';
				else
					return 'dad';
			}
		}
	}

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		#if LUA_ALLOWED
		if(modchartSprites.exists(tag)) return modchartSprites.get(tag);
		if(text && modchartTexts.exists(tag)) return modchartTexts.get(tag);
		if(variables.exists(tag)) return variables.get(tag);
		#end
		return null;
	}

	public function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		//char.setPositionToFeet(stageData.characterFeetPos);
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			// char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0] + char.ox * (char.isPlayer == playsAsBF() ? 250 : -250);
		char.y += char.positionArray[1];

		// if (char == gf && abot != null) {
		// 	abot.y = gfGroup.y + 310 + char.positionArray[1];
		// }
	}

	#if hxCodec
	public function startVideoCodec(name:String)
	{
		#if VIDEOS_ALLOWED
		inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FunkinFileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		return;
		#end
	}
	#end

	public var videoCutscene:VideoSprite = null;
	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true)
	{
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FunkinFileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile)
		{
			videoCutscene = new VideoSprite(fileName, forMidSong, canSkip, loop);
			if(forMidSong) videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong)
			{
				function onVideoEnd()
				{
					if (!isDead && generatedMusic && PlayState.SONG.notes[Std.int(curStep / 16)] != null && !endingSong && !isCameraOnForcedPos)
					{
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead) GameOverSubstate.instance.add(videoCutscene);
			else add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd()
	{
		if (FlxG.state != this)
			return;

		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			precacheList.set('dialogue', 'sound');
			precacheList.set('dialogueClose', 'sound');
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	// For being able to mess with the sprites on Lua
	public var countdownThree:FlxSprite; //Just 3
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	public var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
	public var introSounds:Array<String> = ['intro3', 'intro2', "intro1", "introGo"];

	function cacheCountdown()
	{
		var introAlts:Array<String> = introAssets.get('default');
		if (isPixelStage) introAlts = introAssets.get('pixel');

		for (asset in introAlts)
			Paths.image(asset);

		for (sound in introSounds)
			Paths.sound(sound + introSoundsSuffix);
	}

	public function generateStrums() {
		if (skipCountdown || startOnTime > 0)
			skipArrowStartTween = true;

		generateStaticArrows(0);
		generateStaticArrows(1);
		for (i in 0...playerStrums.length) {
			setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
			setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
		}
		for (i in 0...opponentStrums.length) {
			setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
			setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
			// if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
		}

		if (ClientPrefs.data.ogGameControls && Note.maniaKeys < 10) enableVSliceControls();
	}

	public var defaultPlayerNotePositions:Array<Dynamic> = [-360, -140, 140, 360];
	public function startCountdown()
	{
		// if (waitReady)
		// 	return false;

		#if HSC_ALLOWED if (scripts.event("onStartCountdown", new CancellableEvent()).cancelled) return false; #end

		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		if (replayData == null && !cpuControlled) mobileManager.hitbox.visible = true;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != FunkinLua.Function_Stop) {
			if (!canStart) {
				canStart = true;
				add(waitReadySpr);
				return false;
			}
			if (!GameClient.isConnected())
				generateStrums();

			startedCountdown = true;
			canPause = true;

			Conductor.songPosition = -Conductor.crochet * 5;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted', null);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				characterBopper(tmr.loopsLeft);

				var introAlts:Array<String> = introAssets.get('default');
				var antialias:Bool = ClientPrefs.data.antialiasing;
				if(isPixelStage) {
					introAlts = introAssets.get('pixel');
					antialias = false;
				}
				var tick:Countdown = THREE;

				#if HSC_ALLOWED
				var event:CountdownEvent = scripts.event("onCountdown", EventManager.get(CountdownEvent).recycle(
					swagCounter,
					0.6,
					introSounds[swagCounter] + introSoundsSuffix,
					introAlts[swagCounter],
					1, antialias, null, null, null));
				#end
		
				switch (swagCounter)
				{
					case 0:
						tick = THREE;
					case 1:
						tick = TWO;
					case 2:
						tick = ONE;
					case 3:
						tick = GO;
					case 4:
						tick = START;
				}

				// love when mods do this
				try {
					#if HSC_ALLOWED
					switch (tick)
					{
						case THREE:
							if (event.spritePath != null) countdownThree = createCountdownSprite(event.spritePath, event.antialiasing);
						case TWO:
							if (event.spritePath != null) countdownReady = createCountdownSprite(event.spritePath, event.antialiasing);
						case ONE:
							if (event.spritePath != null) countdownSet = createCountdownSprite(event.spritePath, event.antialiasing);
						case GO:
							if (event.spritePath != null) countdownGo = createCountdownSprite(event.spritePath, event.antialiasing);
						default:
					}
					if (event.soundPath != null) FlxG.sound.play(Paths.sound(event.soundPath), event.volume);
					#else
					//hsc is not default still, so this is here because or that.
					switch (tick)
					{
						case THREE:
							if (introAlts[swagCounter] != null) countdownThree = createCountdownSprite(introAlts[swagCounter], antialias);
						case TWO:
							if (introAlts[swagCounter] != null) countdownReady = createCountdownSprite(introAlts[swagCounter], antialias);
						case ONE:
							if (introAlts[swagCounter] != null) countdownSet = createCountdownSprite(introAlts[swagCounter], antialias);
						case GO:
							if (introAlts[swagCounter] != null) countdownGo = createCountdownSprite(introAlts[swagCounter], antialias);
						default:
					}
					if (introSounds[swagCounter] != null) FlxG.sound.play(Paths.sound(introSounds[swagCounter] + introSoundsSuffix), 0.6);
					#end
				}
				catch (exc) {
					trace(exc);
				}

				notes.forEachAlive(function(note:Note) {
					if(ClientPrefs.data.opponentStrums || isPlayerNote(note))
					{
						note.copyAlpha = false;
						note.noteAlpha = note.multAlpha;
						if (ClientPrefs.data.middleScroll && !isPlayerNote(note))
							note.noteAlpha *= 0.35;
					}
				});

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);
				scripts.event("onPostCountdown", event);

				swagCounter += 1;
			}, 5);
		}
		#if HSC_ALLOWED
		scripts.call("onPostStartCountdown");
		#end
		return true;
	}

	/* V-Slice Mobile Controls */
	public function enableVSliceControls() {
		//I took this from PsychEngine's discord server and make it to work with HScript Improved (.hsc), now I'm using it on source code 😂
		// Credit: @allaxnofake (Discord)
		// https://discord.com/channels/922849922175340586/1395222169037836430 (This link sends you to directly the original post)

		/* Actual Code */
		for (player in 0...2) {
			var strumGroup = player == 1 ? playerStrums : opponentStrums;
			if (Note.maniaKeys != 4)
			{
				var strumLineX:Float = 0;
				var strumWidth = 6 * Note.swagScaledWidth - (Note.getNoteOffsetX() * (Note.maniaKeys - 1));
				var gap:Int = 150;
				if (Note.maniaKeys == 9) gap = 140;
				for (i in 0...Note.maniaKeys) {
					var strumLineX:Float = 0;
					if (isPlayerStrumNote(player))
					{
						if (Note.maniaKeys == 9) strumLineX = FlxG.width / 2 - strumWidth / 0.85 + (gap * i);
						else if (Note.maniaKeys == 8) strumLineX = FlxG.width / 2 - strumWidth / 1 + (gap * i);
						else if (Note.maniaKeys == 7) strumLineX = FlxG.width / 2 - strumWidth / 1.2 + (gap * i);
						else if (Note.maniaKeys == 6) strumLineX = FlxG.width / 2 - strumWidth / 1.5 + (gap * i);
						else if (Note.maniaKeys == 5) strumLineX = FlxG.width / 2 - strumWidth / 1.9 + (gap * i);
						if (Note.maniaKeys >= 5) strumGroup.members[i].x = strumLineX;
					} else {
						strumGroup.members[i].visible = false;
						strumGroup.members[i].x = 9999;
					}
				}
			}
			else
			{
				for (i in 0...4) {
					if (isPlayerStrumNote(player))
					{
						strumGroup.members[i].screenCenter(X);
						strumGroup.members[i].x += defaultPlayerNotePositions[i];
					}
					else
					{
						strumGroup.members[i].y = 40;
						strumGroup.members[i].x = 10 + (i * 65);
						strumGroup.members[i].scale.x = strumGroup.members[i].scale.x / 1.75;
						strumGroup.members[i].scale.y = strumGroup.members[i].scale.y / 1.75;
					}
				}
			}
			if (isPlayerStrumNote(player)) {
				for (i in 0...unspawnNotes.length)
				{
					if (player == 1 && !unspawnNotes[i].mustPress || player == 0 && unspawnNotes[i].mustPress)
						unspawnNotes[i].visible = false;
				}
				fixHitboxPos(strumGroup, (Note.maniaKeys == 4 ? true : false));
			}
		}
		reloadPlayStateHitbox("V Slice");
		//mobileManager.hitbox.cameras = [camHUD];
	}

	public static var hitboxPositions:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0, 0];
	public function fixHitboxPos(strumGroup:StrumLine, ?keyCountIsDefault:Bool) {
		if (keyCountIsDefault) {
			hitboxPositions[0] = Std.int(strumGroup.members[0].x) - 20;
			hitboxPositions[1] = Std.int(strumGroup.members[1].x) - 20;
			hitboxPositions[2] = Std.int(strumGroup.members[2].x) - 20;
			hitboxPositions[3] = Std.int(strumGroup.members[3].x) - 20;
		} else {
			var hitboxFixPos:Float = 10;
			if (Note.maniaKeys == 7) hitboxFixPos = 13;
			if (Note.maniaKeys == 8) hitboxFixPos = 12.5;
			if (Note.maniaKeys == 9) hitboxFixPos = 15;

			for (i in 0...9) {
				if (strumGroup.members[i] != null)
					hitboxPositions[i] = strumGroup.members[i].x - hitboxFixPos;
			}
		}
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();
		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));
		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		var spriteTween:FlxTween; //CNE Thing Lol
		spriteTween = FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		callOnScripts('onCreateCountdownSprite', [spr, spriteTween]);
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		if (replayPlayer != null) {
			replayPlayer.timeJump(time);
		}

		if (nicomments != null) {
			nicomments.timeJump(time);
		}

		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				//daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.destroy();
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				//daNote.kill();
				notes.remove(daNote, true);
				daNote.destroy();
			}
			--i;
		}
	}

	public function updateScore(miss:Bool = false, ?skipRest:Bool = false)
	{
		var points = FlxMath.roundDecimal(
			online.FunkinPoints.fcalcFP(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo)
		, 2);
		if (points != songPoints) {
			songPoints = points;
			GameClient.send("updateSongFP", Math.ffloor(songPoints));
			if (totalPlayed != 0) {
				var maxPoints = online.FunkinPoints.calcFP(1, 0, songDensity, totalPlayed, totalPlayed);
				pointsPercent = Math.min(1, Math.max(0, points / maxPoints));
			}
			resetRPC(true);
		}
		songPoints = points;

		var scoreTextObject = scoreTxt;
		if (GameClient.isConnected()) {
			updateScoreSID(GameClient.room.sessionId);
			return;
		}

		var str:String = ratingName ?? '?';
		if (totalPlayed != 0) {
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
			str += ' ($percent%) - $ratingFC';
		}

		scoreTextObject.text = Language.getText("PlayState.updateScore.scoreTextObject", [
			FlxStringUtil.formatMoney(songScore, false),
			songMisses,
			str
		]);

		if (skipRest) {
			if (ClientPrefs.data.showFP)
				addFPToScoreTxt(scoreTextObject);
			return;
		}

		if (ClientPrefs.data.scoreZoom && !miss && !cpuControlled) {
			if (scoreTxtTween != null) {
				scoreTxtTween.cancel();
			}
			scoreTextObject.scale.x = 1.075;
			scoreTextObject.scale.y = 1.075;
			scoreTxtTween = FlxTween.tween(scoreTextObject.scale, {x: 1, y: 1}, 0.2, {
				onComplete: function(twn:FlxTween) {
					scoreTxtTween = null;
				}
			});
		}
		callOnScripts('onUpdateScore', [miss]);
		if (ClientPrefs.data.showFP)
			addFPToScoreTxt(scoreTextObject);
	}

	function addFPToScoreTxt(scoreTextObject:FlxText) {
		if (ClientPrefs.data.newFPPreview)
			scoreTextObject.text += ' | FP: ' + songPoints + ' (V5: ${FlxMath.roundDecimal(online.FunkinPoints.devFP(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo), 2)})';
		else
			scoreTextObject.text += ' | FP: ' + songPoints + ' (${CoolUtil.floorDecimal(pointsPercent * 100, 1)}%)';
	}

	public function setSongTime(time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = time;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
		}
		if (Conductor.songPosition <= opponentVocals.length) {
			opponentVocals.time = time;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
		}
		vocals.play();
		opponentVocals.play();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}
	
	function getPresencePoints() {
		if (songPoints == 0)
			return "";

		if (songPoints < 0) {
			var aasss = '${songPoints}'.split('');
			aasss.insert(1, ' ');
			return ' - ${aasss.join('')}FP';
		}
		
		return ' - ${songPoints}FP';
	}

	function startSong():Void
	{
		#if HSC_ALLOWED scripts.call("onSongStart"); #end
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500));
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		stagesFunc(function(stage:BaseStage) stage.startSong());

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		if (gf?.speaker is ABotSpeaker)
			cast(gf.speaker, ABotSpeaker).snd = FlxG.sound.music;

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")" + ' [${Note.maniaKeys}k]' + getPresencePoints(), iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');
		#if HSC_ALLOWED scripts.call("onStartSong"); #end
	}

	var debugNum:Int = 0;
	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private function generateSong(dataPath:String):Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		if (songData.needsVoices) {
			try {
				var playerVocals = Paths.voices(curSong, boyfriend.vocalsFile, songSuffix);
				if (playerVocals == null) playerVocals = Paths.voices(curSong, 'Player', songSuffix);
				vocals.loadEmbedded(playerVocals ?? Paths.voices(curSong, null, songSuffix));
				
				var oppVocals = Paths.voices(curSong, dad.vocalsFile, songSuffix);
				if (oppVocals == null) oppVocals = Paths.voices(curSong, 'Opponent', songSuffix);
				if(oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
			}
			catch (exc:Dynamic) {
				//vocals.loadEmbedded(Paths.voices(curSong, null, songSuffix));
			}
		}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound().loadEmbedded(Paths.inst(curSong, songSuffix));
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		var noteData:Array<SwagSection>;

		// NEW SHIT
		noteData = songData.notes;

		var file:String = Paths.json(songName + '/events' + songSuffix);
		var fileCNE:String = Paths.getPath('songs/' + songName + '/events' + songSuffix + '.json', TEXT, null, true);
		#if MODS_ALLOWED
		if (FunkinFileSystem.exists(Paths.modsJson(songName + '/events' + songSuffix)) || FunkinFileSystem.exists(file) || !FunkinFileSystem.exists(file) && FunkinFileSystem.exists(fileCNE)) {
		#else
		if (OpenFlAssets.exists(file) || !OpenFlAssets.exists(file) && OpenFlAssets.exists(fileCNE)) {
		#end
			var eventsData:Array<Dynamic> = Song.loadFromJson('events' + songSuffix, songName).events;
			trace("eventsData: " + eventsData);
			for (event in eventsData) //Event Notes
				for (i in 0...event[1].length)
					makeEvent(event, i);
		}

		var playingNoteCount:Float = 0;
		// var playingTime:Float = 0;
		var lastStrumTime:Float = 0;

		var isPsychRelease = (songData.format ?? '').startsWith('psych_v1');

		Song.updateManiaKeys(SONG);

		if (maniaModifier == Note.maniaKeys) {
			maniaModifier = null;
		}

		var dataNotes:Array<Dynamic> = [];
		var dataNotesSection:Array<Int> = [];

		for (sectIndex => section in noteData) {
			for (note in section.sectionNotes) {
				dataNotes.push(note.copy());
				dataNotesSection.push(sectIndex);
			}
		}

		haxe.ds.ArraySort.sort(dataNotes, function(a:Array<Dynamic>, b:Array<Dynamic>):Int {
			if (a == null || b == null) {
				return 0;
			}

			return Std.int(a[0] - b[0]);
		});

		function getMustPressFromRaw(section:SwagSection, rawNote:Array<Dynamic>):Bool {
			var gottaHitNote:Bool = section.mustHitSection;
			if (!isPsychRelease) {
				if (rawNote[1] > Note.maniaKeys - 1) {
					gottaHitNote = !section.mustHitSection;
				}
			}
			else {
				gottaHitNote = rawNote[1] < Note.maniaKeys;
			}
			return gottaHitNote;
		}
		
		// MULTIKEY NOTES CONVERSION ALGO!!!
		// also shoutouts to bromaster

		if (maniaModifier != null) {
			function scaleKeyToNew(noteData:Int):Int {
				return Math.round(noteData * ((maniaModifier - 1) / (Note.maniaKeys - 1))) % maniaModifier;
			}
			function scaleKeyBack(noteData:Int):Int {
				return Math.round(noteData * ((Note.maniaKeys - 1) / (maniaModifier - 1))) % Note.maniaKeys;
			}

			var friendNotes:Array<Array<Int>> = [];
		
			//initial note adoption
			if (Note.maniaKeys > maniaModifier) {
				for (noteData in 0...Note.maniaKeys) {
					friendNotes[noteData] ??= [];
					friendNotes[noteData].push(scaleKeyToNew(noteData));
				}
			}
			else {
				for (newNoteData in 0...maniaModifier) {
					friendNotes[scaleKeyBack(newNoteData)] ??= [];
					friendNotes[scaleKeyBack(newNoteData)].push(newNoteData);
				}
			}

			trace("NEW Note Mapping: " + friendNotes);

			var notesCount:Array<Int> = [for (_ in 0...Note.maniaKeys) 0];
			// var bonusCount:Array<Int> = [for (_ in 0...maniaModifier) 0];
			var jackStack:Array<Int> = [-1, -1];
			var fuckStack:Array<Int> = [-1, -1];

			// var method:String = 'rando3';

			function nextNoteData(daNoteData:Int, mustPress:Int) {
				var daNoteDataFull:Int = daNoteData + (Note.maniaKeys * (mustPress));

				// switch (method) {
				// 	case 'mapping': {
						var noteMaps = friendNotes[daNoteData];
						if (jackStack[mustPress] == -1 || jackStack[mustPress] != daNoteData) {
							notesCount[daNoteDataFull]++;
						}
						// jackStack[mustPress] = note[2] <= 0 ? daNoteData : -1;
						jackStack[mustPress] = daNoteData;
						return noteMaps[notesCount[daNoteDataFull] % noteMaps.length];
			// 		}
			// 		case 'rando3': {
			// 			var noteMaps = friendNotes[daNoteData];
			// 			var scaledNote = noteMaps[notesCount[daNoteDataFull]++ % noteMaps.length];
			// 			if (fuckStack[mustPress] == scaledNote + (++bonusCount[daNoteDataFull] % 3 - 1)) {
			// 				bonusCount[daNoteDataFull]++;
			// 			}
			// 			var newKey = scaledNote + (bonusCount[daNoteDataFull] % 3 - 1);
			// 			return fuckStack[mustPress] = (Std.int(Math.abs(newKey) % (maniaModifier)));
			// 		}
			// 	}
			// 	return daNoteData;
			}
			
			for (i => note in dataNotes) {
				var daNoteDataSide:Int = Std.int(Std.int(note[1]) / Note.maniaKeys);
				var daNoteData:Int = Std.int(note[1] % Note.maniaKeys);
				var mustPress:Int = cast getMustPressFromRaw(noteData[dataNotesSection[i]], note);

				note[1] = nextNoteData(daNoteData, mustPress);
				note[1] += maniaModifier * daNoteDataSide;
			}

			trace('Converted from: ' + Note.maniaKeys + 'k');
			Note.maniaKeys = maniaModifier;
		}

		trace('Song Keys: ' + Note.maniaKeys + 'k');

		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType) {
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		for (i => songNotes in dataNotes) {
			var section = noteData[dataNotesSection[i]];
			var daStrumTime:Float = songNotes[0];
			if (daStrumTime > inst.length)
				continue;
			var daNoteData:Int = Std.int(songNotes[1] % Note.maniaKeys);
			if (songNotes[1] < 0 || songNotes[1] > Note.maniaKeys * 2 - 1) // this should prevent most exe mods from crashing
				continue;

			var strumLineID:Int = 0;
			if (songNotes.length > 4) {
				strumLineID = Std.int(songNotes[4]);
			} else {
				var isPlayerNote:Bool = section.mustHitSection;
				if (!isPsychRelease) {
					if (songNotes[1] > Note.maniaKeys - 1) {
						isPlayerNote = !section.mustHitSection;
					}
				}
				else {
					isPlayerNote = songNotes[1] < Note.maniaKeys;
				}
				strumLineID = (isPlayerNote ? 1 : 0);
			}

			var oldNote:Note;
			if (unspawnNotes.length > 0)
				oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
			else
				oldNote = null;

			var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote);
			
			swagNote.strumLineID = strumLineID;
			swagNote.mustPress = !strumLines.members[strumLineID].cpu;

			swagNote.sustainLength = songNotes[2];
			swagNote.gfNote = (section.gfSection && (songNotes[1] < Note.maniaKeys));
			swagNote.noteType = songNotes[3];
			if(!Std.isOfType(songNotes[3], String)) swagNote.noteType = ChartingState.noteTypeList[songNotes[3]]; //Backward compatibility + compatibility with Week 7 charts

			if (noBadNotes && (swagNote.hitCausesMiss || swagNote.hitHealth < 0)) {
				swagNote.destroy();
				continue;
			}

			swagNote.scrollFactor.set();

			var susLength:Float = swagNote.sustainLength;
			susLength = susLength / Conductor.stepCrochet;
			unspawnNotes.push(swagNote);

			var floorSus:Int = Math.floor(susLength);
			if(floorSus > 0) {
				for (susNote in 0...floorSus+1)
				{
					oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

					var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote), daNoteData, oldNote, true);
					sustainNote.strumLineID = strumLineID;
					sustainNote.mustPress = !strumLines.members[strumLineID].cpu;
					sustainNote.gfNote = (section.gfSection && (songNotes[1]<Note.maniaKeys));
					sustainNote.noteType = swagNote.noteType;
					sustainNote.scrollFactor.set();
					swagNote.tail.push(sustainNote);
					sustainNote.parent = swagNote;
					unspawnNotes.push(sustainNote);
					
					sustainNote.correctionOffset = swagNote.height / 2;
					if(!PlayState.isPixelStage)
					{
						if(oldNote.isSustainNote)
						{
							oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
							oldNote.scale.y /= playbackRate;
							oldNote.updateHitbox();
						}

						if(ClientPrefs.data.downScroll)
							sustainNote.correctionOffset = 0;
					}
					else if(oldNote.isSustainNote)
					{
						oldNote.scale.y /= playbackRate;
						oldNote.updateHitbox();
					}

					if (sustainNote.mustPress) sustainNote.followX += FlxG.width / 2; // general offset
					else if(ClientPrefs.data.middleScroll)
					{
						sustainNote.followX += 310;
						if(daNoteData > 1) //Up and Right
						{
							sustainNote.followX += FlxG.width / 2 + 25;
						}
					}
				}
			}

			if (isPlayerNote(swagNote)) {
				if (daStrumTime - lastStrumTime > 10)
					playingNoteCount++;

				lastStrumTime = daStrumTime;
			}

			if (swagNote.mustPress)
			{
				swagNote.followX += FlxG.width / 2; // general offset
			}
			else if(ClientPrefs.data.middleScroll)
			{
				swagNote.followX += 310;
				if(daNoteData > 1) //Up and Right
				{
					swagNote.followX += FlxG.width / 2 + 25;
				}
			}

			if(!noteTypes.contains(swagNote.noteType)) {
				noteTypes.push(swagNote.noteType);
			}
		}
		// songDensity = 1 + (playingNoteCount == 0 ? 0 : playingNoteCount / playingTime / 2);
		// trace("note density score: " + songDensity + ' for total of ${playingNoteCount} notes');

		songDensity = playingNoteCount == 0 ? 0 : playingNoteCount / (inst.length / playbackRate / 1000) / 2;
		trace("note density score: " + songDensity + ' for total of ${playingNoteCount} notes');
		trace("note density power: " + online.FunkinPoints.densityPower(songDensity) + 'DP');

		var maxFP = online.FunkinPoints.calcFP(1, 0, songDensity, playingNoteCount, playingNoteCount);
		trace("max points: ~" + maxFP + 'FP');
		if (ClientPrefs.data.newFPPreview) {
			var maxFP = online.FunkinPoints.devFP(1, 0, songDensity, playingNoteCount, playingNoteCount);
			trace("max points: ~" + maxFP + 'FP');
		}

		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		unspawnNotes.sort(sortByTime);
		generatedMusic = true;
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);
			
			case 'Play Sound':
				precacheList.set(event.value1, 'sound');
				Paths.sound(event.value1);

			case 'Set Health Icon':
				new HealthIcon(event.value2);

			case 'Focus Camera':
				sectionCameraMovement = false;
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != FunkinLua.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public static function getKeysArray(keys:Int) {
		if (keys == 4)
			return ['note_left', 'note_down', 'note_up', 'note_right'];

		return [for (i in 0...keys) '${keys}k_note_${i + 1}'];
	}

	public var skipArrowStartTween:Bool = false; //for lua
	inline private function generateStaticArrows(player:Int):Void
	{
		var strumGroup = (player == 0 ? strumLines.members[0] : strumLines.members[1]);
		if (replayPlayer == null && ClientPrefs.data.noteUnderlayOpacity > 0 && strumGroup == getPlayerStrums(true) && ClientPrefs.data.noteUnderlayType == 'All-In-One') {
			var vsliceControlFix:Float = 1;
			if (ClientPrefs.data.ogGameControls && Note.maniaKeys < 10) {
				switch (Note.maniaKeys) {
					case 4: vsliceControlFix = 6.5 / 3.5;
					case 5: vsliceControlFix = 6.5 / 5;
					case 6: vsliceControlFix = 6.5 / 4.8;
					case 7: vsliceControlFix = 6.5 / 4.6;
					case 8: vsliceControlFix = 6.5 / 4.8;
					case 9: vsliceControlFix = 6.5 / 4.5;
				}
			}
			var underlay = new FlxSprite().makeGraphic(1, FlxG.width * 2, FlxColor.BLACK);
			underlay.alpha = ClientPrefs.data.noteUnderlayOpacity;
			underlay.scale.x = (Note.swagScaledWidth * Note.maniaKeys - (Note.getNoteOffsetX() * (Note.maniaKeys - 1))) * vsliceControlFix;

			underlay.updateHitbox();
			noteUnderlays.add(underlay);
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		if (isCreated) {
			stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
			if (paused)
			{
				if (FlxG.sound.music != null)
				{
					FlxG.sound.music.pause();
					vocals.pause();
					opponentVocals.pause();
				}

				if (startTimer != null && !startTimer.finished) startTimer.active = false;
				if (finishTimer != null && !finishTimer.finished) finishTimer.active = false;
				if (songSpeedTween != null) songSpeedTween.active = false;

				var chars:Array<Character> = [boyfriend, gf, dad];
				for (char in chars)
					if(char != null && char.colorTween != null)
						char.colorTween.active = false;

				#if LUA_ALLOWED
				for (tween in modchartTweens) tween.active = false;
				for (timer in modchartTimers) timer.active = false;
				#end
			}
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		if (isCreated) {
			stagesFunc(function(stage:BaseStage) stage.closeSubState());
			if (paused) {
				resume();
				callOnScripts('onResume');
				resetRPC(startTimer != null && startTimer.finished);
			}
		}

		super.closeSubState();
		if (GameClient.isConnected()) {
			if (mobileManager?.hitbox != null) mobileManager.hitbox.visible = true;
			if (mobileManager?.mobilePad != null) mobileManager.mobilePad.visible = true;
		}

		effectMusic(FlxG.sound.music, true);
		effectMusic(vocals, true);
		effectMusic(opponentVocals, true);
	}

	override public function onFocus():Void
	{
		if (isCreated && health > 0 && !paused) resetRPC(Conductor.songPosition > 0.0);
		super.onFocus();
	}

	override public function onFocusLost():Void
	{
		#if DISCORD_ALLOWED
		if (isCreated && health > 0 && !paused) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")" + ' [${Note.maniaKeys}k]' + getPresencePoints(), iconP2.getCharacter());
		#end

		super.onFocusLost();
	}

	// Updating Discord Rich Presence.
	function resetRPC(?cond:Bool = false)
	{
		#if DISCORD_ALLOWED
		if (cond)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")" + ' [${Note.maniaKeys}k]' + getPresencePoints(), iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")" + ' [${Note.maniaKeys}k]' + getPresencePoints(), iconP2.getCharacter());
		#end
	}

	public function resyncVocals():Void
	{
		if(finishTimer != null) return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals)
		{
			if (Conductor.songPosition <= vocals.length)
			{
				voc.time = Conductor.songPosition;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			}
	
		}
		#if HSC_ALLOWED scripts.call("onVocalsResync"); #end
	}

	public var paused(default, set):Bool = false;
	function set_paused(v) {
		if (forcePause && !v)
			return paused;

		for (group in [boyfriendGroup, dadGroup, gfGroup]) {
			if (group == null)
				continue;

			for (character in group) {
				if (!(character is Character))
					continue;

				var char:Character = cast(character);

				if (char.sound == null)
					continue;

				if (v)
					char.sound.pause();
				else
					char.sound.resume();
			}
		}
		return paused = v;
	}
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	public var canPause:Bool = true;
	var freezeCamera:Bool = false;

	public var disableForceShow:Bool = false;

	var lastLagPos:Float = 0;
	var isPlayNoteNear:Bool = false;

	function toggleOpponentMode() {
		if (replayPlayer != null)
			return;
		opponentMode = !opponentMode;
		if (replayRecorder != null) {
			remove(replayRecorder);
			replayRecorder.destroy();
		}
		songScore = 0;
		boyfriend.isPlayer = !boyfriend.isPlayer;
		dad.isPlayer = !dad.isPlayer;
		forceInvalidScore = true;
		addHealth(2);
	}

	public function addMisses(value:Int) { songMisses += value; }
	public function addHits(value:Int) { songHits += value; }

	var nearNoteValue:Float = 0;
	final NEAR_NOTE_DISTANCE:Float = 1500;

	override public function update(elapsed:Float)
	{
		if (forcePause)
			return;

		if (!isCreated) {
			if (!asyncLoop.started) {
				asyncLoop.start();
			}

			super.update(elapsed);
			return;
		}

		scripts.call("update", [elapsed]);

		final canInput = checkCanInput();

		if (FlxG.keys.justPressed.F7) {
			ClientPrefs.data.showFP = !ClientPrefs.data.showFP;
			ClientPrefs.saveSettings();
			updateScore();
		}

		if(FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.P)
			playOtherSide = !playOtherSide;

		if (FlxG.keys.justPressed.F2) {
			ClientPrefs.data.disableSubmiting = !ClientPrefs.data.disableSubmiting;
			ClientPrefs.saveSettings();
			Alert.alert("Replay Submiting: " + (ClientPrefs.data.disableSubmiting ? "OFF" : "ON"));
		}

		if (FlxG.keys.justPressed.F3) {
			ClientPrefs.data.debugMode = !ClientPrefs.data.debugMode;
			ClientPrefs.saveSettings();
			Alert.alert("Debug Mode: " + (ClientPrefs.data.debugMode ? "ON" : "OFF"));
		}
		
		if (!GameClient.isConnected()) {
			if (!ClientPrefs.data.disableLagDetection
				&& !finishingSong
				&& elapsed >= 0.1
				&& Conductor.songPosition > lastLagPos
				&& isPlayNoteNear) 
			{
				setSongTime(Conductor.songPosition - 2000);
				lastLagPos = Conductor.songPosition + 3000; // don't tp for another 3s starting from last lag pos
				Alert.alert("Mod Lag Detected (-2s)");
			}

			// if (FlxG.keys.justPressed.F6) {
			// 	swingMode = !swingMode;
			// }

			// if (FlxG.keys.justPressed.F8 && replayPlayer == null) {
			// 	opponentMode = !opponentMode;
			// 	if (replayRecorder != null) {
			// 		remove(replayRecorder);
			// 		replayRecorder.destroy();
			// 	}
			// 	songScore = 0;
			// 	boyfriend.isPlayer = !boyfriend.isPlayer;
			// 	dad.isPlayer = !dad.isPlayer;
			// 	addHealth(2);
			// }

			if (cpuControlled) {
				var shiftMult = (mobileButtonPressed('X') || FlxG.keys.pressed.SHIFT) ? 3 : 1;
				if (controls.UI_LEFT) {
					if (playbackRate - elapsed * 0.25 * shiftMult > 0)
						playbackRate -= elapsed * 0.25 * shiftMult;
					if (playbackRate < 0.01) {
						playbackRate = 0.01;
					}
					botplayTxt.text = "BOTPLAY\n" + '(${CoolUtil.floorDecimal(playbackRate, 2)}x)';
				}
				else if (controls.UI_RIGHT) {
					playbackRate += elapsed * 0.25 * shiftMult;
					if (playbackRate > 8) {
						playbackRate = 8;
					}
					botplayTxt.text = "BOTPLAY\n" + '(${CoolUtil.floorDecimal(playbackRate, 2)}x)';
				}
				else if (mobileButtonJustPressed('Y') || controls.RESET) {
					playbackRate = 1;
					botplayTxt.text = "BOTPLAY";
				}
			}
		}

		if (FlxG.keys.justPressed.F11 && GameClient.isConnected()) {
			GameClient.reconnect(5); //delay the reconnection for 5 seconds (for testing)
		}

		if (controls.TAUNT && canInput && (!canSpaceTaunt ? !FlxG.keys.justPressed.SPACE : true)) {
			var altSuffix = FlxG.keys.pressed.ALT ? '-alt' : '';
			self.playAnim('taunt' + altSuffix, true);
			if (GameClient.isConnected())
				GameClient.send("charPlay", ["taunt" + altSuffix]);
		}

		//should fix realtime cpu switch lag.
		notes.forEachAlive(function(note:Note) {
			if (note.mustPress == strumLines.members[getStrumFromNote(note)].cpu) {
				note.mustPress = !strumLines.members[getStrumFromNote(note)].cpu;
			}
		});

		/*if (FlxG.keys.justPressed.NINE)
		{
			iconP1.swapOldIcon();
		}*/
		callOnScripts('onUpdate', [elapsed]);

		//why 0?
		//FlxG.camera.followLerp = 0;

		if(!inCutscene && !paused && !freezeCamera) {
			//FlxG.camera.followLerp = FlxMath.bound(elapsed * 2.4 * cameraSpeed * playbackRate / (FlxG.updateFramerate / 60), 0, 1);
			if (ClientPrefs.data.oldCameraSystem) {
				var lerpVal = Math.max(0, Math.min(1, elapsed * 2.4 * cameraSpeed * playbackRate));
				camFollowPos.setPosition(FlxMath.lerp(camFollowPos.x, camFollow.x, lerpVal), FlxMath.lerp(camFollowPos.y, camFollow.y, lerpVal));
			}
			else
			{
				FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			}
			if(!startingSong && !endingSong && self.animation.curAnim != null && self.animation.curAnim.name.startsWith('idle')) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}
		
		for (camera in cameras) {
			if (!ClientPrefs.data.flashing)
				camera.stopFlash();
			if (!ClientPrefs.data.camShakes)
				camera.stopShake();
			if (!ClientPrefs.data.camZooms) {
				camera.zoom = 1.0;

				if (camera == FlxG.camera)
					FlxG.camera.zoom = defaultCamZoom;
				if (camera == camHUD)
					camHUD.zoom = defaultHUDCamZoom;
			}
			if (!ClientPrefs.data.camAngles) {
				// flixel bug will allow 0.X angles for some reason
				camera.angle = 0.0;
			}
			if (!ClientPrefs.data.camMovement) {
				moveCamera(playsAsBF(), true);
				camera.snapToTarget();
			}
			//FIXME some way to force update the variables???
		}

		super.update(elapsed);

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		if (controls.PAUSE && (GameClient.isConnected() ? isReady : startedCountdown) && canPause && canInput)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != FunkinLua.Function_Stop) {
				openPauseMenu();
			}
		}

		if (GameClient.isConnected()) {
			//if player 2 left then go back to lobby // nvm, unreliable on reconnects
			// if (!GameClient.reconnecting && GameClient.room.state.player2.name == "") {
			// 	trace("No one is playing, leaving...");
			// 	endSong();
			// }

			if (!isReady && (controls.mobileControls && FlxG.mouse.justPressed || controls.ACCEPT) && !inCutscene && canStart && canInput) {
				isReady = true;
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
				if (ClientPrefs.data.flashing)
					freakyFlicker = FlxFlicker.flicker(waitReadySpr, 0.5, 0.05, true, false, _ -> waitReadySpr.text = "waiting for other player...");
				GameClient.send("playerReady");
			}

			if (waitReady) {
				paused = true;
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
		}

		// "!inCutscene" it's called a DEBUG button for a reason
		if (controls.justPressed('debug_1') && !endingSong && canInput)
			openChartEditor();

		var iconOffset:Int = 30 + (iconP1s.length > 1 || iconP2s.length > 1 ? 10 : 0);
		if (health > 2) health = 2;
		else if (health < 0) health = 0;

		for (i => icon in iconP1s) {
			icon.alpha = iconP1.alpha;
			icon.visible = iconP1.visible;
			icon.angle = iconP1.angle;

			var mult:Float = FlxMath.lerp(iconOriginalScale * iconSizeMult(iconP1s), icon.scale.x, FlxMath.bound(1 - (elapsed * 9 * playbackRate), 0, 1));
			icon.scale.set(mult, mult);
			icon.updateHitbox();

			icon.x = healthBar.barCenter + (150 * icon.scale.x - 150) / 2 - iconOffset;
			icon.y = healthBar.y - 75;
			if (icon.animation.curAnim != null)
				icon.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0;

			addIconOffset(icon, true, i);
		}

		for (i => icon in iconP2s) {
			icon.alpha = iconP2.alpha;
			icon.visible = iconP2.visible;
			icon.angle = iconP2.angle;

			var mult:Float = FlxMath.lerp(iconOriginalScale * iconSizeMult(iconP2s), icon.scale.x, FlxMath.bound(1 - (elapsed * 9 * playbackRate), 0, 1));
			icon.scale.set(mult, mult);
			icon.updateHitbox();

			icon.x = healthBar.barCenter - (150 * icon.scale.x) / 2 - iconOffset * 2;
			icon.y = healthBar.y - 75;
			if (icon.animation.curAnim != null)
				icon.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0;

			addIconOffset(icon, false, i);
		}

		if (controls.justPressed('debug_2') && !endingSong && canInput)
			openCharacterEditor();
		
		if (startedCountdown && !paused)
		{
			Conductor.songPosition += FlxG.elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= 0)
			{
				var timeDiff:Float = Math.abs(FlxG.sound.music.time - Conductor.songPosition - Conductor.offset);
				Conductor.songPosition = FlxMath.lerp(Conductor.songPosition, FlxG.sound.music.time, FlxMath.bound(elapsed * 2.5, 0, 1));
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}
		}

		if (!paused && startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= 0)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(ClientPrefs.data.timeBarType == 'Time Elapsed') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			if(ClientPrefs.data.timeBarType != 'Song Name')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal / playbackRate, false);
		}

		//realtime update for camera follow, this can fix lot's of things
		if (SONG?.notes[curSection] != null && ClientPrefs.data.alterCamera && generatedMusic && !endingSong && !isCameraOnForcedPos)
		{
			moveCameraSection();
		}

		if (camZooming && ClientPrefs.data.alterCamera)
		{
			FlxG.camera.zoom = lerp(FlxG.camera.zoom, defaultCamZoom, camGameZoomLerp);
			camHUD.zoom = lerp(camHUD.zoom, defaultHUDCamZoom, camHUDZoomLerp);
		}
		else if (camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, FlxMath.bound(1 - (elapsed * 3.125 * camZoomingDecay * playbackRate), 0, 1));
			camHUD.zoom = FlxMath.lerp(defaultHUDCamZoom, camHUD.zoom, FlxMath.bound(1 - (elapsed * 3.125 * camZoomingDecay * playbackRate), 0, 1));
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!GameClient.isConnected() && !ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong && canInput && replayData == null && !cpuControlled)
		{
			subsHealth(9999);
			trace("RESET = True");
		}
		doDeathCheck();

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime * (Conductor.judgePlaybackRate == null || playbackRate < Conductor.judgePlaybackRate ? playbackRate : Conductor.judgePlaybackRate);
			if(songSpeed < 1) time /= songSpeed;
			if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				var noteType = dunceNote.noteType;
				var strumlineID = getStrumFromNote(dunceNote);
				var mustHit = dunceNote.mustPress;
				var animSuffix = dunceNote.animSuffix;
				var event = EventManager.get(NoteCreationEvent).recycle(dunceNote, noteType, strumlineID, mustHit, animSuffix);

				if (!scripts.event('onNoteCreation', event).cancelled) {
					notes.insert(0, dunceNote);
					dunceNote.spawned = true;

					callOnLuas('onSpawnNote', [0, dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
					callOnHScript('onSpawnNote', [dunceNote]);
					scripts.event('onPostNoteCreation', event);

					unspawnNotes.shift();
				}

				// insert tesla and einstein png here
				// var index:Int = unspawnNotes.indexOf(dunceNote);
				// unspawnNotes.splice(index, 1);
			}
		}

		isPlayNoteNear = false;
		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled)
					keysCheck();
				else
					playerDance();

				var forceShowOpStrums = false;
				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						notes.forEachAlive(function(daNote:Note)
						{
							var strumGroup:StrumLine = strumLines.members[getStrumFromNote(daNote)];
							var __updateNote_strum:StrumNote = strumGroup.members[daNote.noteData];
							var __updateNote_event:NoteUpdateEvent = this.__updateNote_event;

							__updateNote_event.recycle(daNote, FlxG.elapsed, __updateNote_strum);
							strumGroup.onNoteUpdate.dispatch(__updateNote_event);

							if (__updateNote_strum == null || __updateNote_event.cancelled) {
								return;
							}

							if (!playsAsBF() && !disableForceShow) {
								forceShowOpStrums = ClientPrefs.data.opponentStrums;
								if (forceShowOpStrums) {
									daNote.visible = true;
									daNote.noteAlpha = 1;
								}
							}
							if (__updateNote_event.__reposNote) daNote.followStrumNote(__updateNote_strum, fakeCrochet, songSpeed / playbackRate);

							/* I hope removing this won't effect anything
							if (GameClient.isConnected() && daNote.strumTime <= Conductor.songPosition) {
								camZooming = true;
							}
							*/

							if (isPlayerNote(daNote))
							{
								if (!isPlayNoteNear && daNote.strumTime - Conductor.songPosition < NEAR_NOTE_DISTANCE) {
									isPlayNoteNear = true;
								}

								if(cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition)) {
									goodNoteHit(daNote);
								}
							}
							else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote && (!GameClient.isConnected() || playOtherSide || GameClient.room.state.royalMode))
								opponentNoteHit(daNote);

							if(daNote.isSustainNote && __updateNote_strum.sustainReduce) daNote.clipToStrumNote(__updateNote_strum);

							// Kill extremely late notes and cause misses
							if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
							{
								if (isPlayerNote(daNote) && !cpuControlled &&!daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
									noteMiss(daNote);

								daNote.active = false;
								daNote.visible = false;

								//daNote.kill();
								notes.remove(daNote, true);
								//TODO: don't destroy notes
								daNote.destroy();
							}
						});
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}

				if (forceShowOpStrums) {
					camHUD.visible = true;
					camHUD.alpha = 1;
					for (strum in opponentStrums) {
						if (!strum.forceHide) {
							strum.alpha = 1;
							strum.visible = true;
						}
					}
				}
			}
			checkEventNote();
		}

		if (isPlayNoteNear)
			nearNoteValue = Math.min(1.0, nearNoteValue + elapsed * (1000 / NEAR_NOTE_DISTANCE));
		else
			nearNoteValue = Math.max(0.0, nearNoteValue - elapsed * (1000 / NEAR_NOTE_DISTANCE));

		if (replayPlayer == null && ClientPrefs.data.noteUnderlayOpacity > 0 ) {
			var playingStrums = getPlayerStrums(true);
			for (i in 0...noteUnderlays.length) {
				var underlay = noteUnderlays.members[i];
				var sturm = playingStrums.members[i];
				if (!sturm.active || !sturm.visible) {
					underlay.alpha = 0;
				}
				else {
					underlay.x = sturm.x;
					underlay.angle = sturm.direction - 90;
					underlay.alpha = Math.min(1.0, ClientPrefs.data.noteUnderlayOpacity * sturm.alpha) * nearNoteValue;
				}
			}
		}

		if (!GameClient.isConnected() 
			&& !ClientPrefs.data.disableLagDetection
			&& !finishingSong
			&& elapsed >= 0.1
			&& Conductor.songPosition > lastLagPos
			&& isPlayNoteNear) 
		{
			setSongTime(Conductor.songPosition - 2000);
			lastLagPos = Conductor.songPosition + 3000; // don't tp for another 3s starting from last lag pos
			Alert.alert("Mod Lag Detected (-2s)");
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		if (ClientPrefs.data.oldCameraSystem) {
			setOnScripts('cameraX', camFollowPos.x);
			setOnScripts('cameraY', camFollowPos.y);
		} else {
			setOnScripts('cameraX', camFollow.x);
			setOnScripts('cameraY', camFollow.y);
		}
		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);

		if (botplayTxt != null) {
			if (botplayTxt.visible != botplayVisibility)
				botplayTxt.visible = botplayVisibility;

			if (botplayTxt.visible) {
				botplaySine += 180 * elapsed;
				botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
			}
		}

		if (Conductor.songPosition >= FlxG.sound.music.length) {
			finishSong();
		}

		scripts.call("postUpdate", [elapsed]);
	}

	function addIconOffset(icon:HealthIcon, isP1:Bool, i:Int) {
		switch ((isP1 ? iconP1s : iconP2s).length) {
			case 2:
				if (i == 0) {
					if (isP1)
						icon.x += 20;
					else
						icon.x -= 20;
					icon.y += 20;
				}
				else {
					if (isP1)
						icon.x -= 20;
					else
						icon.x += 20;
					icon.y -= 20;
				}

				if (isP1)
					icon.x += 75 * iconSizeMult(iconP1s);
			case 3:
				switch (i) {
					case 0:
						if (isP1)
							icon.x += 20;
						else
							icon.x -= 20;
						icon.y += 20;
					case 1:
						if (isP1)
							icon.x += 20;
						else
							icon.x -= 20;
						icon.y -= 20;
					case 2:
						if (isP1)
							icon.x -= 20;
						else
							icon.x += 20;
				}

				if (isP1)
					icon.x += 75 * iconSizeMult(iconP1s);
		}
	}

	function iconSizeMult(from:Array<HealthIcon>):Float {
		if (from.length <= 1)
			return 1;

		if (from.length <= 2)
			return 0.65;

		return 0.6;
	}

	function effectMusic(sound:FlxSound, ?stop:Bool = false) {
		effectSound(sound, [
			AL.FILTER_TYPE => AL.FILTER_LOWPASS
		], stop ? [] : [
			AL.LOWPASS_GAIN => 1,
			AL.LOWPASS_GAINHF => 0.015,
		]);
	}

	function effectSound(sound:FlxSound, filtersI:Map<Int, Int>, filtersF:Map<Int, Float>) @:privateAccess {
		final handle = sound?._channel?.__audioSource?.__backend?.handle;

		if (handle == null)
			return;

		var filter = AL.createFilter();

		for (type => value in filtersI) {
			AL.filteri(filter, type, value);
		}

		for (type => value in filtersF) {
			AL.filterf(filter, type, value);
		}

		AL.sourcei(handle, AL.DIRECT_FILTER, filter);
	}

	function openPauseMenu()
	{
		if (!canPause || subState is PauseSubState /*|| GameClient.isConnected()*/)
			return;

		if (!GameClient.isConnected()) {
			pause();
		}
		else {
			effectMusic(FlxG.sound.music);
			effectMusic(vocals);
			effectMusic(opponentVocals);
		}

		if(!cpuControlled)
		{
			for (strum in getAllPlayerStrums()) {
				for (note in strum)
					if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
					{
						note.playAnim('static');
						note.resetAnim = 0;
					}
			}
		}

		if (GameClient.isConnected()) {
			if (mobileManager?.hitbox != null) mobileManager.hitbox.visible = false;
			if (mobileManager?.mobilePad != null) mobileManager.mobilePad.visible = false;
		}
		openSubState(new PauseSubState(self.getScreenPosition().x, self.getScreenPosition().y));
		//}

		#if DISCORD_ALLOWED
		DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")" + ' [${Note.maniaKeys}k]' + getPresencePoints(), iconP2.getCharacter());
		#end
	}

	function pause() {
		if (!ClientPrefs.data.oldCameraSystem) FlxG.camera.followLerp = 0;
		mobileManager.mobilePad.visible = persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
	}

	function resume() {
		if (forcePause)
			return;

		mobileManager.mobilePad.visible = true;
		if (FlxG.sound.music != null && !startingSong) {
			resyncVocals();
		}

		if (startTimer != null && !startTimer.finished)
			startTimer.active = true;
		if (finishTimer != null && !finishTimer.finished)
			finishTimer.active = true;
		if (songSpeedTween != null)
			songSpeedTween.active = true;

		var chars:Array<Character> = [boyfriend, gf, dad];
		for (char in chars)
			if (char != null && char.colorTween != null)
				char.colorTween.active = true;

		#if LUA_ALLOWED
		for (tween in modchartTweens)
			tween.active = true;
		for (timer in modchartTimers)
			timer.active = true;
		#end

		paused = false;
	}

	function openChartEditor()
	{
		if (GameClient.isConnected() || redditMod)
			return;

		if (!ClientPrefs.data.oldCameraSystem) FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		chartingMode = true;
		replayData = null;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end
		
		FlxG.switchState(() -> new ChartingState());
	}

	function openCharacterEditor()
	{
		if (GameClient.isConnected() || redditMod)
			return;

		if (!ClientPrefs.data.oldCameraSystem) FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		replayData = null;
		cancelMusicFadeTween();
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		FlxG.switchState(() -> new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	public var gameOverTimer:FlxTimer;
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (!GameClient.isConnected() && ((skipHealthCheck && instakillOnMiss) || (playsAsBF() ? health <= 0 : health >= 2)) && !practiceMode && !isDead && replayPlayer == null && gameOverTimer == null)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != FunkinLua.Function_Stop) {
				self.stunned = true;
				deathCounter++;

				paused = true;
				canPause = false;
				#if VIDEOS_ALLOWED
				if(videoCutscene != null)
				{
					videoCutscene.destroy();
					videoCutscene = null;
				}
				#end

				persistentUpdate = false;
				persistentDraw = false;
				#if LUA_ALLOWED
				for (tween in modchartTweens) {
					tween.active = true;
				}
				for (timer in modchartTimers) {
					timer.active = true;
				}
				#end

				FlxG.camera.setFilters([]);

				if (stage3D != null)
					stage3D.onDeath();

				function ded() {
					openSubState(new GameOverSubstate(
						self.getScreenPosition().x - self.positionArray[0], 
						self.getScreenPosition().y - self.positionArray[1], 
						camFollow.x, camFollow.y,
						(self.deadName != null || (self.animExists('firstDeath') && self.animExists('deathLoop')) ? self : null)
					));
				}

				if(GameOverSubstate.deathDelay > 0)
				{
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
					{
						vocals.stop();
						opponentVocals.stop();
						FlxG.sound.music.stop();
						ded();
						gameOverTimer = null;
					});
				}
				else
				{
					vocals.stop();
					opponentVocals.stop();
					FlxG.sound.music.stop();
					ded();
				}

				// FlxG.switchState(() -> new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his own variable because it's only used here
				DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function tweenCameraZoom(zoom:Float, duration:Float, direct:Bool, ease:Null<Float->Float>) {
		if (Math.isNaN(zoom) || Math.isNaN(duration))
			return;

		if (cameraTwn != null)
			cameraTwn.cancel();
		cameraTwn = FlxTween.tween(this, {forceCameraZoom: zoom * (direct ? FlxCamera.defaultZoom : stageData.defaultZoom)}, duration, {ease: ease, onComplete: twn -> {cameraTwn = null;}});
	}

	var cameraTwnPos:FlxTween;
	public function tweenCameraToFollowPoint(duration:Float, ease:Null<Float->Float>) {
		if (cameraTwnPos != null)
			cameraTwnPos.cancel();

		FlxG.camera.follow(null);
		var followPos:FlxPoint = camFollow.getPosition() - FlxPoint.weak(FlxG.camera.width * 0.5, FlxG.camera.height * 0.5);
		cameraTwnPos = FlxTween.tween(FlxG.camera.scroll, {x: followPos.x, y: followPos.y}, duration, {ease: ease, onComplete: (_) -> {
			FlxG.camera.follow(camFollow, LOCKON, 0);
		}});
	}

	public function tweenCameraToPosition(x:Float, y:Float, duration:Float, ease:Null<Float->Float>) {
		camFollow.setPosition(x, y);
		tweenCameraToFollowPoint(duration, ease);
	}

	public function checkEventNote() {
		while(eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if(eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	//Make HScript Improved Functions Call-able from Normal HScript & Lua
	public function hscriptImprovedCall(value1:String, value2:String) {
		var scriptPacks:Array<ScriptPack> = [scripts, stateScripts];
		var args:Array<String> = value2.split(',');

		for (pack in scriptPacks) {
			pack.call(value1, args);
			//public functions
			if (pack.publicVariables.exists(value1)) {
				var func = pack.publicVariables.get(value1);
				if (func != null && Reflect.isFunction(func))
					Reflect.callMethod(null, func, args);
			}
		}

		//static functions
		if (Script.staticVariables.exists(value1)) {
			var func = Script.staticVariables.get(value1);
			if (func != null && Reflect.isFunction(func))
				Reflect.callMethod(null, func, args);
		}
	}

	private var camEventUsed:Bool = false;
	public var eventsTween:Map<String, FlxTween> = [];
	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case "Camera Movement":
				curCameraTarget = Std.parseInt(value1);
				//force the camera
				if (Std.parseInt(value1) > -1) camEventUsed = true;
				else camEventUsed = false;
			case "Camera Position":
				// 1. Clear previous movement
				var tween = eventsTween.get("cameraMovement");
				if (tween != null) {
					if (tween.onComplete != null) tween.onComplete(tween);
					tween.cancel();
				}

				// 2. Combine the two split strings back into one list of parameters
				var v1:Array<String> = value1.split(', ');
				var v2:Array<String> = value2.split(', ');
				
				// Helper to get params easily (casting strings to correct types)
				var pX:Float = Std.parseFloat(v1[0]);
				var pY:Float = Std.parseFloat(v1[1]);
				var pSmooth:Bool = (v1[2] == "true");
				var pDuration:Float = (v1[3] != null) ? Std.parseFloat(v1[3]) : 4.0;
				
				var pEase:String = (v2[0] != null) ? v2[0] : "linear";
				var pEaseParam:String = (v2[1] != null) ? v2[1] : ""; // Used for eases like backIn
				var pIsOffset:Bool = (v2[2] == "true");

				// 3. Execution Logic
				curCameraTarget = -1; // Force manual override
				
				var targetX:Float = pIsOffset ? (camFollow.x + pX) : pX;
				var targetY:Float = pIsOffset ? (camFollow.y + pY) : pY;
				
				camFollow.setPosition(targetX, targetY);

				if (!pSmooth) {
					FlxG.camera.snapToTarget();
				} 
				else if (pEase != "CLASSIC") {
					var oldFollow = FlxG.camera.followEnabled;
					FlxG.camera.followEnabled = false;

					eventsTween.set("cameraMovement", FlxTween.tween(FlxG.camera.scroll, {
						x: camFollow.x - FlxG.camera.width * 0.5, 
						y: camFollow.y - FlxG.camera.height * 0.5
					}, (Conductor.stepCrochet / 1000) * pDuration, {
						ease: CoolUtil.flxeaseFromString(pEase, pEaseParam),
						onComplete: function(twn:FlxTween) {
							FlxG.camera.followEnabled = oldFollow;
							eventsTween.remove("cameraMovement");
						}
					}));
				}
			//Codename Engine Support (you can't use these in the editor, just there for compatibility)
			case 'Camera Flash':
				//make the event work on PsychEngine
				var splittedValue1 = value1.split(', ');
				var splittedValue2 = value2.split(', ');
				var flValue:Null<Float> = Std.parseFloat(splittedValue2[0]);
				var stringToBool:Bool = splittedValue1[0] == 'true' ? true : false;
				var getColor:Dynamic = CoolUtil.getColorFromDynamic(splittedValue1[1]); //I'm not sure, If color is wrong tell me

				var camera:FlxCamera = splittedValue2[1] == "camHUD" ? camHUD : camGame;
				if (stringToBool) // reversed
					camera.fade(getColor, (Conductor.stepCrochet / 1000) * flValue, false, () -> {camera._fxFadeAlpha = 0;}, true);
				else // Not Reversed
					camera.flash(getColor, (Conductor.stepCrochet / 1000) * flValue, null, true);

				/*
				"Camera Flash" => [
					{name: "Reversed?", type: TBool, defValue: false},
					{name: "Color", type: TColorWheel, defValue: "#FFFFFF"},
					{name: "Time (Steps)", type: TFloat(0.25, 9999, 0.25, 2), defValue: 4},
					{name: "Camera", type: TDropDown(['camGame', 'camHUD']), defValue: "camHUD"}
				]
				*/
			//Most important Event in the Codename Engine (Tested & It doesn't work for now)
			case "HScript Call":
				hscriptImprovedCall(value1, value2);

			case 'Must Hit Camera':
				var isFren = value1 == "gf";
				var isDad = isFren ? (SONG.notes[curSection]?.mustHitSection ?? true) != true : value1 == "dad";

				var options = value2.split(",");
				for (i => option in options)
					if (option == 'null' || option.trim() == '')
						options[i] = null;

				moveCamera(isDad, isFren, Std.parseFloat(options[2] ?? '0'), Std.parseFloat(options[3] ?? '0'));

				var durSeconds = Conductor.stepCrochet * (Std.parseFloat(options[0] ?? '4')) / 1000;
				var ease = options[1] ?? 'CLASSIC';
				var easeFunction:Null<Float->Float> = null;
				if (ease != null && ease != 'CLASSIC') {
					if (ease == "INSTANT") {
						FlxG.camera.snapToTarget();
					}
					else {
						easeFunction = Reflect.field(FlxEase, ease);
						tweenCameraToFollowPoint(durSeconds, easeFunction);
					}
				}

			case 'Tween Camera Zoom': //brokne
				var s1 = value1.split(",");
				var s2 = value2.split(",");

				var zoom = Std.parseFloat(s1[0]) ?? 1;
				var duration = Conductor.stepCrochet * (Std.parseFloat(s1[1]) ?? 4) / 1000;
				var ease = s2[0] ?? 'linear';
				var isDirectMode = s2[1] ?? 'direct' == 'direct'; // else stage mode

				var easeFunction:Null<Float->Float> = null;
				if (ease != null && ease != "INSTANT") {
					easeFunction = Reflect.field(FlxEase, ease);
				}

				tweenCameraZoom(zoom, duration, isDirectMode, easeFunction);

			case 'Change Camera Bop':
				if (flValue1 == null) flValue1 = DEFAULT_ZOOM_RATE;
				if (flValue2 == null) flValue2 = 1;

				cameraBopIntensity = (DEFAULT_BOP_INTENSITY - 1.0) * flValue2 + 1.0;
				hudCameraZoomIntensity = (DEFAULT_BOP_INTENSITY - 1.0) * flValue2 * 2.0;
				cameraZoomRate = Std.int(flValue1);

			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf') && Paths.formatToSongPath(SONG.song) == 'tutorial') { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;

						for (char in characters) {
							if (char.isPlayer != dad.isPlayer)
								continue;
				
							char.playAnim('cheer', true);
							char.specialAnim = true;
							char.heyTimer = flValue2;
						}
					} 
					else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;

					for (char in characters) {
						if (char.isPlayer != boyfriend.isPlayer)
							continue;
			
						char.playAnim('hey', true);
						char.specialAnim = true;
						char.heyTimer = flValue2;
					}
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null) {
					char.playAnim(value1, true);
					char.specialAnim = true;
					
					if (char != gf) {
						for (charo in characters) {
							if (charo.isPlayer != char.isPlayer)
								continue;
		
							charo.playAnim(value1, true);
							charo.specialAnim = true;
						}
					}
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						for (char in [boyfriend].concat([for (v in characters) v])) {
							if (!ClientPrefs.data.modchartSkinChanges && char.isSkin)
								continue;

							if (char.isPlayer != boyfriend.isPlayer)
								continue;

							if(char.curCharacter != value2) {
								var charName = value2;
								var daSID = null;
								for (sid => charac in characters) {
									if (char == charac) {
										daSID = sid;
										charName += "__" + sid;
										break;
									}
								}

								if(!boyfriendMap.exists(charName)) {
									addCharacterToList(value2, charType);
								}
	
								var lastAlpha:Float = char.alpha;
								char.alpha = 0.00001;

								var isHard = char == boyfriend;
								char = boyfriendMap.get(charName);
								if (isHard)
									boyfriend = char;
								if (daSID != null)
									characters.set(daSID, char);

								char.alpha = lastAlpha;
								iconP1s[char.gameIconIndex].changeIcon(char.healthIcon);
							}
						}
						
						setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						for (char in [dad].concat([for (v in characters) v])) {
							if (!ClientPrefs.data.modchartSkinChanges && char.isSkin)
								continue;

							if (char.isPlayer != dad.isPlayer)
								continue;

							if(char.curCharacter != value2) {
								var charName = value2;
								var daSID = null;
								for (sid => charac in characters) {
									if (char == charac) {
										daSID = sid;
										charName += "__" + sid;
										break;
									}
								}

								if(!dadMap.exists(charName)) {
									addCharacterToList(value2, charType);
								}
	
								var wasGf:Bool = char.curCharacter.startsWith('gf-') || char.curCharacter == 'gf';
								var lastAlpha:Float = char.alpha;
								char.alpha = 0.00001;

								var isHard = char == dad;
								char = dadMap.get(charName);
								if (isHard)
									dad = char;
								if (daSID != null)
									characters.set(daSID, char);

								if(!char.curCharacter.startsWith('gf-') && char.curCharacter != 'gf') {
									if(wasGf && gf != null) {
										gf.visible = true;
									}
								} else if(gf != null) {
									gf.visible = false;
								}
								char.alpha = lastAlpha;
								iconP2s[char.gameIconIndex].changeIcon(char.healthIcon);
							}
						}

						setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								gf = gfMap.get(value2);
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}
				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(this, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					if (e.message != null)
						addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
				}
			
			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);

			case '3D Camera Follow Point':
				if (stage3D != null)
					stage3D.setFollowCamera(value1);

			case 'Set Health Icon':
				for (icon in (value1 == '1' ? iconP2s : iconP1s)) {
					icon.changeIcon(value2);
				}

			case 'Focus Camera':
				if (value1 == '0' || value1 == '1')
					moveCamera(value1 == '1');
				else if (value1 == '2')
					moveCamera(false, true);
		}
		
		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	public var sectionCameraMovement:Bool = true;

	var prevMustHit:Null<Bool> = null;
	public function moveCameraSection(?sec:Null<Int>):Void {
		if (!sectionCameraMovement) return;

		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;
		if(SONG.notes[sec] == null) return;

		if (SONG.notes[sec].targetCamera != null) {
			newMoveCamera(camEventUsed ? curCameraTarget : SONG.notes[sec].targetCamera); //Will be main thing in the future
		}

		if(prevMustHit != null && prevMustHit == SONG.notes[sec].mustHitSection) return;
		prevMustHit = SONG.notes[sec].mustHitSection;
		if (SONG.notes[sec].targetCamera == null) {
			moveCamera(SONG.notes[sec].mustHitSection != true, SONG.notes[sec].gfSection);
		}
	}

	var cameraLookAt:Int = 1;

	var cameraTwn:FlxTween;
	var cameraTwnX:FlxTween;
	var cameraTwnY:FlxTween;
	public function newMoveCamera(strum:Int = 0, ?tX:Float, ?tY:Float)
    {
        var strumChar = dad; //focus dad if nothing is found.
        if (strumLines != null) {
            if (strumLines.members[strum] != null) {
                if (strumLines.members[strum].characters[0] != null)
                    strumChar = strumLines.members[strum].characters[0];
            }
        }

        var posX = strumChar.getMidpoint().x;
        var posY = strumChar.getMidpoint().y;
        if (strum == 0) {
            posX += 150;
            posY -= 100;
        } else if (strum == 1) {
            posX -= 100;
            posY -= 100;
        }

        curCameraTarget = strum;

        setCamPosFromChar(strumChar, tX + posX, tY + posY);

        if (strumChar != null && strumChar.codenameOffsets == true)
        {
            if (generatedMusic && strumLines.members[curCameraTarget] != null)
            {
                var pos = FlxPoint.get();
                var r = 0;
                for(c in strumLines.members[curCameraTarget].characters) {
                    if (c == null || !c.visible) continue;
                    var cpos = c.getCameraPosition();
                    pos.x += cpos.x;
                    pos.y += cpos.y;
                    r++;
                    //cpos.put();
                }
                if (r > 0) {
                    pos.x /= r;
                    pos.y /= r;

                    var event = scripts.event("onCameraMove", EventManager.get(CamMoveEvent).recycle(pos, strumLines.members[curCameraTarget], r));
                    if (!event.cancelled)
                        camFollow.setPosition(pos.x, pos.y);
                }
                pos.put();
            }
        }

        callOnScripts('onCameraMove', [curCameraTarget]);
        var curCameraChar = 'none';
        switch(curCameraTarget) {
            case 0: curCameraChar = 'dad';
            case 1: curCameraChar = 'bf';
            case 2: curCameraChar = 'gf';
        }
        callOnScripts('onMoveCamera', [curCameraChar]);
    }

    public function setCamPosFromChar(char:Character, x:Float, y:Float) {
        if (char != null) {
            //get these from character
            var camOffsetOG:FlxPoint = char.cameraOffset;
            var camPos:Array<Float> = char.cameraPosition;

            if (ClientPrefs.data.oldCameraSystem) camFollow.set(x, y);
            else camFollow.setPosition(x, y);

            if (char == boyfriend) camFollow.x -= camPos[0] + camOffsetOG.x;
            else camFollow.x += camPos[0] + camOffsetOG.x;

            camFollow.y += camPos[1] + camOffsetOG.y;
            if (char == boyfriend) {
                if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
                {
                    cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
                        function (twn:FlxTween)
                        {
                            cameraTwn = null;
                        }
                    });
                }

                cameraLookAt = 1;
                if (stage3D != null)
                    stage3D.setFollowCamera('bf');
            } else if (char == dad) {
                tweenCamIn();
                cameraLookAt = 0;
                if (stage3D != null)
                    stage3D.setFollowCamera('dad');
            } else if (char == gf) {
                tweenCamIn();
                if (stage3D != null)
                    stage3D.setFollowCamera('gf');
            }
        }
    }

	public function moveCamera(isDad:Bool, ?toGirlfren:Bool = false, ?tX:Float, ?tY:Float)
	{
		if (toGirlfren && gf != null) {
			if (ClientPrefs.data.oldCameraSystem) camFollow.set(tX + gf.getMidpoint().x, tY + gf.getMidpoint().y);
			else camFollow.setPosition(tX + gf.getMidpoint().x, tY + gf.getMidpoint().y);
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			tweenCamIn();
			if (stage3D != null)
				stage3D.setFollowCamera('gf');
			curCameraTarget = 2;
			callOnScripts('onMoveCamera', ['gf']);
			callOnScripts('onCameraMove', [curCameraTarget]);
			return;
		}

		if(isDad)
		{
			if (ClientPrefs.data.oldCameraSystem) camFollow.set(tX + dad.getMidpoint().x + 150, tY + dad.getMidpoint().y - 100);
			else camFollow.setPosition(tX + dad.getMidpoint().x + 150, tY + dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
			cameraLookAt = 0;
			if (stage3D != null)
				stage3D.setFollowCamera('dad');
			curCameraTarget = 0;
			callOnScripts('onMoveCamera', ['dad']);
			callOnScripts('onCameraMove', [curCameraTarget]);
		}
		else
		{
			if (ClientPrefs.data.oldCameraSystem) camFollow.set(tX + boyfriend.getMidpoint().x - 100, tY + boyfriend.getMidpoint().y - 100);
			else camFollow.setPosition(tX + boyfriend.getMidpoint().x - 100, tY + boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}

			cameraLookAt = 1;

			if (stage3D != null)
				stage3D.setFollowCamera('bf');
			curCameraTarget = 1;
			callOnScripts('onMoveCamera', ['boyfriend']);
			callOnScripts('onCameraMove', [curCameraTarget]);
		}
	}

	public function tweenCamIn() {
		if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	var finishingSong:Bool = false;
	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		if (finishingSong) return;
		finishingSong = true;

		updateTime = false;
		FlxG.sound.music.volume = 0;
		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();
		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}

	public var skipResults = false;

	public var transitioning = false;
	var canEndSongOnline:Bool = false;

	public function endSong()
	{
		#if HSC_ALLOWED if (scripts.event("onSongEnd", new CancellableEvent()).cancelled) return false; #end
		mobileManager.hitbox.visible = false;

		if (!canEndSongOnline && GameClient.isConnected()) {
			GameClient.send("updateSongFP", Math.ffloor(songPoints));
			GameClient.send("updateMaxCombo", maxCombo);
			GameClient.send("playerEnded");
			return false;
		}

		if (redditMod) {
			health = 0;
			doDeathCheck();
			return false;
		}

		songPoints = online.FunkinPoints.calcFP(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo);

		//Should kill you if you tried to cheat
		if(!startingSong) {
			notes.forEach(function(daNote:Note) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					subsHealth(0.05 * healthLoss);
				}
			});
			for (daNote in unspawnNotes) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					subsHealth(0.05 * healthLoss);
				}
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var noMissWeek:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([noMissWeek, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger', '1000combo']);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != FunkinLua.Function_Stop && !transitioning)
		{
			replayData = null;

			var prevHighscore = Highscore.getScore(SONG.song + '${Note.maniaKeys == 4 ? '' : '$' + Note.maniaKeys + 'k'}', storyDifficulty);

			#if !switch
			var percent:Float = ratingPercent;
			var gainedPoints:Float = 0;
			if(Math.isNaN(percent)) percent = 0;
			if (!isInvalidScore() && finishingSong) {
				Highscore.saveScore(SONG.song + '${Note.maniaKeys == 4 ? '' : '$' + Note.maniaKeys + 'k'}', songScore, storyDifficulty, percent);
				var offlinePoints = online.FunkinPoints.save(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo);
				if (!online.network.FunkinNetwork.loggedIn)
					gainedPoints = offlinePoints;
				if (replayRecorder != null) {
					gainedPoints = replayRecorder.save();
				}
			}
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (!GameClient.isConnected() && replayPlayer != null) {
				online.gui.Alert.alert("Calculated Points from Replay", "+" + songPoints);
			}

			if (GameClient.isConnected()) {
				if (isInvalidScore()) online.gui.Alert.alert("Calculated Points", "+" + songPoints);
				online.states.ResultsState.gainedPoints = gainedPoints;
				if (!skipResults)
					FlxG.switchState(() -> new online.states.ResultsState());
				else
					FlxG.switchState(() -> new online.states.RoomState());
			}
			else if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					states.TitleState.playFreakyMusic();
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					cancelMusicFadeTween();
					if(FlxTransitionableState.skipNextTransIn) {
						CustomFadeTransition.nextCamera = null;
					}
					FlxG.switchState(() -> new StoryMenuState());

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !isInvalidScore()) {
						trace('saving week performance for: ' + WeekData.getWeekFileName());
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;
					if (ClientPrefs.data.oldCameraSystem) prevCamFollowPos = camFollowPos;

					PlayState.loadSong(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					cancelMusicFadeTween();
					LoadingState.loadAndSwitchState(new PlayState());
				}
			}
			else
			{
				trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				cancelMusicFadeTween();
				if(FlxTransitionableState.skipNextTransIn) {
					CustomFadeTransition.nextCamera = null;
				}
				FreeplayState.gainedPoints = gainedPoints;
				FlxG.switchState(() -> new online.states.ResultsSoloState({
					hitNotes: songHits,
					combo: maxCombo,
					sicks: songSicks,
					goods: songGoods,
					bads: songBads,
					shits: songShits,
					misses: songMisses,
					score: songScore,
					accuracy: ratingPercent,
					isHighscore: songScore > prevHighscore,
					difficultyName: Difficulty.getString(),
					songName: SONG.song,
					character: playsAsBF() ? boyfriend.resultsName ?? boyfriend.curCharacter : dad.resultsName ?? dad.curCharacter,
					points: songPoints,
					mania: maniaModifier
				}));
				changedDifficulty = false;
			}
			transitioning = true;
		}
		return true;
	}

	public function KillNotes() {
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;

			//daNote.kill();
			notes.remove(daNote, true);
			daNote.destroy();
		}
		unspawnNotes = [];
		eventNotes = [];
	}

	public var totalPlayed(default, null):Int = 0;
	public var totalNotesHit(default, null):Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;
	public var noteTimingRating:FlxText;
	public var noteTimingRatingTween:FlxTween;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	// stores the last judgement object
	var lastRating:FlxSprite;
	var lastOtherRatings:Map<String, FlxSprite> = new Map();
	// stores the last combo sprite object
	var lastCombo:FlxSprite;
	// stores the last combo score objects in an array
	var lastScore:Array<FlxSprite> = [];
	var lastOtherScore:Map<String, Array<FlxSprite>> = new Map();
	public var downscroll:Bool = ClientPrefs.data.downScroll;

	inline private function cachePopUpScore()
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		if (!ClientPrefs.data.disableComboRating)
			for (rating in ratingsData)
				Paths.image(uiPrefix + rating.image + uiSuffix);
		if (!ClientPrefs.data.disableComboCounter)
			for (i in 0...10)
				Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	inline function recycleComboSprite():FlxTweenedSprite {
		var v:FlxTweenedSprite = cast comboGroup.recycle(FlxTweenedSprite);
		v.reset(0, 0);
		v.velocity.set(0, 0);
		v.offset.set(0, 0);
		v.origin.set(0, 0);
		v.scale.set(1, 1);
		v.alpha = 1.0;
		v.visible = true;
		v.color = FlxColor.WHITE;
		v.angle = 0;
		v.tween = null;

		if (lastRating == v) lastRating = null;
		if (lastCombo == v) lastCombo = null;

		for (score in lastScore) {
			if (score == v)
				lastScore.remove(score);
		}

		for (sid => sprite in lastOtherRatings) {
			if (sprite == v)
				lastOtherRatings.remove(sid);
		}

		for (sid => sprites in lastOtherScore) {
			for (sprite in sprites) {
				if (sprite == v)
					sprites.remove(sprite);
			}
			lastOtherScore.set(sid, sprites);
		}

		return v;
	}

	function getComboOffset(bfSide:Bool) {
		if (!GameClient.isConnected()) {
			return ClientPrefs.data.comboOffset;
		}

		if (!bfSide)
			return ClientPrefs.data.comboOffsetOP1;
		else
			return ClientPrefs.data.comboOffsetOP2;
	}

	function getRatingOffset(?forSID:String) {
		var placementX:Float = FlxG.width * 0.35;
		var placementY:Float = 0;
		if (GameClient.isConnected() && forSID != null) {
			var char = characters.get(forSID);
			if (char != null) {
				placementX = FlxG.width * (0.4 + (char.isPlayer == playsAsBF() ? 0.15 : -0.1));
				if (ClientPrefs.data.verticalRatingPos) {
					placementY = char.ox * 250;
				}
				else {
					placementX += char.ox * (char.isPlayer == playsAsBF() ? 250 : -250);
				}
			}
		}
		return [placementX, placementY];
	}

	inline private function popUpScoreOP(ratingImage:String, ?forSID:String) {
		var placement = getRatingOffset(forSID);
		var playerStats = GameClient.isConnected() ? getPlayerStats(forSID) : null;

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal") {
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage)
				uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		var rating:FlxTweenedSprite = null;
		if (!ClientPrefs.data.disableComboRating) {
			rating = recycleComboSprite();
			rating.loadGraphic(Paths.image(uiPrefix + ratingImage + uiSuffix));
			rating.cameras = [camHUD];
			rating.screenCenter();
			rating.x = placement[0] - 40;
			rating.y -= 60;
			rating.y += placement[1];
			rating.acceleration.y = 550 * playbackRate * playbackRate;
			rating.velocity.y = -(FlxG.random.int(140, 175) * playbackRate);
			rating.velocity.x = -(FlxG.random.int(0, 10) * playbackRate);
			rating.alpha = 1.0;
			rating.visible = (!ClientPrefs.data.hideHud && showRating);
			rating.x += getComboOffset(playerStats?.player?.bfSide ?? false)[0];
			rating.y -= getComboOffset(playerStats?.player?.bfSide ?? false)[1];
			rating.antialiasing = antialias;

			if (!ClientPrefs.data.comboStacking) {
				if (lastOtherRatings.exists(forSID))
					lastOtherRatings.get(forSID).kill();
				lastOtherRatings.set(forSID, rating);
			}

			comboGroup.remove(rating, true);
			comboGroup.add(rating);

			if (!PlayState.isPixelStage) {
				rating.setGraphicSize(Std.int(rating.width * 0.7));
			}
			else {
				rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			}

			rating.updateHitbox();

			rating.color = FlxColor.WHITE;
			if (ClientPrefs.data.colorRating) {
				switch (ratingImage) {
					case 'shit':
						rating.color = COLOR_SHIT;
					case 'bad':
						rating.color = COLOR_BAD;
					case 'good':
						rating.color = COLOR_GOOD;
					case 'sick':
						rating.color = COLOR_SICK;
				}
			}

			rating.tween = FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
				startDelay: Conductor.crochet * 0.001 / playbackRate,
				onComplete: function(tween:FlxTween) {
					rating.kill();
				}
			});
		}

		if (!ClientPrefs.data.disableComboCounter) {
			var colorCombo:FlxColor = FlxColor.WHITE;
			if (ClientPrefs.data.colorRating && GameClient.isConnected()) {
				if (playerStats?.player != null && playerStats.player.misses == 0) {
					if (playerStats.player.shits > 0)
						colorCombo = COLOR_SHIT;
					else if (playerStats.player.bads > 0)
						colorCombo = COLOR_BAD;
					else if (playerStats.player.goods > 0)
						colorCombo = COLOR_GOOD;
					else if (playerStats.player.sicks > 0)
						colorCombo = COLOR_SICK;
				} 
			}

			var seperatedScore:Array<Int> = [];

			var playerCombo = playerStats?.combo ?? opponentNoteHits;

			if (playerCombo >= 1000) {
				seperatedScore.push(Math.floor(playerCombo / 1000) % 10);
			}
			seperatedScore.push(Math.floor(playerCombo / 100) % 10);
			seperatedScore.push(Math.floor(playerCombo / 10) % 10);
			seperatedScore.push(playerCombo % 10);

			if (lastOtherScore.exists(forSID)) {
				var lastOPScore = lastOtherScore.get(forSID);
				while (lastOPScore.length > 0) {
					lastOPScore[0].kill();
					lastOPScore.remove(lastOPScore[0]);
				}
			}

			var daLoop:Int = 0;
			var xThing:Float = 0;

			if (showComboNum)
				for (i in seperatedScore) {
					var numScore:FlxTweenedSprite = recycleComboSprite();
					numScore.loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
					numScore.cameras = [camHUD];
					numScore.screenCenter();
					numScore.x = placement[0] + (43 * daLoop) - 90 + getComboOffset(playerStats?.player?.bfSide ?? false)[2];
					numScore.y += placement[1] + 80 - getComboOffset(playerStats?.player?.bfSide ?? false)[3];

					if (!ClientPrefs.data.comboStacking) {
						var lastOPScore = lastOtherScore.get(forSID) ?? [];
						lastOPScore.push(numScore);
						lastOtherScore.set(forSID, lastOPScore);
					}

					if (!PlayState.isPixelStage)
						numScore.setGraphicSize(Std.int(numScore.width * 0.5));
					else
						numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
					numScore.updateHitbox();

					numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					numScore.velocity.y = -(FlxG.random.int(140, 160) * playbackRate);
					numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
					numScore.alpha = 1.0;
					numScore.visible = !ClientPrefs.data.hideHud;
					numScore.antialiasing = antialias;

					comboGroup.remove(numScore, true);
					comboGroup.add(numScore);

					numScore.tween = FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
						onComplete: function(tween:FlxTween) {
							numScore.kill();
						},
						startDelay: Conductor.crochet * 0.002 / playbackRate
					});

					daLoop++;
					if (numScore.x > xThing)
						xThing = numScore.x;

					numScore.color = colorCombo;
				}
		}
	}

	inline private function popUpScore(note:Note = null):Rating
	{
		var noteDiffNoAbs:Float = note.strumTime - (Conductor.judgeSongPosition ?? Conductor.songPosition) + ClientPrefs.getRatingOffset();
		var noteDiff:Float = Math.abs(noteDiffNoAbs);
		getPlayerVocals().volume = 1;

		var placement = getRatingOffset(GameClient.room?.sessionId);
		var rating:FlxTweenedSprite = null;
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / (Conductor.judgePlaybackRate ?? playbackRate));

		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			spawnNoteSplashOnNote(note);

		//if(!practiceMode && !cpuControlled) {
		songScore += score;
		switch (note.rating) {
			case "sick":
				songSicks++;
			case "good":
				songGoods++;
			case "bad":
				songBads++;
			case "shit":
				songShits++;
				combo = 0;
		}

		if(!note.ratingDisabled)
		{
			songHits++;
			totalPlayed++;
			updateScoreSelf(false);
			// RecalculateRating(false);
		}

		if (!practiceMode && !cpuControlled) {
			//todo:  maybe replace with set? idk 
			GameClient.send("addScore", score);
			GameClient.send("addHitJudge", note.rating);
		}
		//}

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		if (!ClientPrefs.data.disableComboRating) {
			rating = recycleComboSprite();
			rating.loadGraphic(Paths.image(uiPrefix + daRating.image + uiSuffix));
			rating.cameras = [camHUD];
			rating.screenCenter();
			rating.x = placement[0] - 40;
			rating.y -= 60;
			rating.y += placement[1];
			rating.acceleration.y = 550 * playbackRate * playbackRate;
			rating.velocity.y = -(FlxG.random.int(140, 175) * playbackRate);
			rating.velocity.x = -(FlxG.random.int(0, 10) * playbackRate);
			rating.alpha = 1.0;
			rating.visible = (!ClientPrefs.data.hideHud && showRating);
			rating.x += getComboOffset(playsAsBF())[0];
			rating.y -= getComboOffset(playsAsBF())[1];
			rating.antialiasing = antialias;

			comboGroup.remove(rating, true);
			comboGroup.add(rating);
			
			if (!ClientPrefs.data.comboStacking)
			{
				if (lastRating != null) lastRating.kill();
				lastRating = rating;
			}

			rating.color = FlxColor.WHITE;
			if (ClientPrefs.data.colorRating) {
				switch (daRating.name) {
					case 'shit':
						rating.color = COLOR_SHIT;
					case 'bad':
						rating.color = COLOR_BAD;
					case 'good':
						rating.color = COLOR_GOOD;
					case 'sick':
						rating.color = COLOR_SICK;
				}
			}

			rating.tween = FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
				startDelay: Conductor.crochet * 0.001 / playbackRate,
				onComplete: function(tween:FlxTween)
				{
					rating.kill();
				}
			});
		}

		var comboSpr:FlxTweenedSprite = null;
		if (showCombo) {
			comboSpr = recycleComboSprite();
			comboSpr.loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
			comboSpr.cameras = [camHUD];
			comboSpr.screenCenter();
			comboSpr.x = placement[0];
			comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			comboSpr.velocity.y = -(FlxG.random.int(140, 160) * playbackRate);
			comboSpr.alpha = 1.0;
			comboSpr.visible = !ClientPrefs.data.hideHud;
			comboSpr.x += getComboOffset(playsAsBF())[0];
			comboSpr.y -= getComboOffset(playsAsBF())[1];
			comboSpr.antialiasing = antialias;
			comboSpr.y += 60 + placement[1];
			comboSpr.velocity.x = FlxG.random.int(1, 10) * playbackRate;
			comboSpr.ID = combo;

			comboGroup.remove(comboSpr, true);
			comboGroup.add(comboSpr);

			if (!ClientPrefs.data.comboStacking) {
				if (lastCombo != null) lastCombo.kill();
				lastCombo = comboSpr;
			}

			comboSpr.tween = FlxTween.tween(comboSpr, {alpha: 0}, 0.1 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					comboSpr.kill();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});
		}

		if (!PlayState.isPixelStage)
		{
			if (rating != null)
				rating.setGraphicSize(Std.int(rating.width * 0.7));
			if (comboSpr != null)
				comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			if (rating != null)
				rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			if (comboSpr != null)
				comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		if (comboSpr != null)
			comboSpr.updateHitbox();
		if (rating != null)
			rating.updateHitbox();

		// i miss kade engine
		if (ClientPrefs.data.showNoteTiming && (!ClientPrefs.data.hideHud && showRating) && noteTimingRating == null) {
			add(noteTimingRating = new FlxText(0, 0, 0, "0ms"));
		}
		if (noteTimingRating != null) {
			switch (daRating.name) {
				case 'shit' | 'bad':
					noteTimingRating.color = FlxColor.RED;
				case 'good':
					noteTimingRating.color = FlxColor.LIME;
				case 'sick':
					noteTimingRating.color = FlxColor.CYAN;
			}
			noteTimingRating.borderStyle = OUTLINE;
			noteTimingRating.borderSize = 1;
			noteTimingRating.borderColor = FlxColor.BLACK;
			noteTimingRating.text = FlxMath.roundDecimal(noteDiffNoAbs / (Conductor.judgePlaybackRate ?? playbackRate), 3) + "ms";
			noteTimingRating.size = 20;
			noteTimingRating.camera = camHUD;
			noteTimingRating.alpha = 1;
			noteTimingRating.active = true;

			if (noteTimingRatingTween != null) {
				noteTimingRatingTween.cancel();
			}

			noteTimingRating.screenCenter();
			noteTimingRating.x = placement[0] + getComboOffset(playsAsBF())[0] + 100;
			noteTimingRating.y += placement[1] + -getComboOffset(playsAsBF())[1] + 60 + (comboSpr?.height ?? 0);
			noteTimingRating.acceleration.y = 600;
			noteTimingRating.velocity.y -= 150;
			noteTimingRating.velocity.x += comboSpr?.velocity?.x ?? (FlxG.random.int(1, 10) * playbackRate);

			noteTimingRatingTween = FlxTween.tween(noteTimingRating, {alpha: 0}, 0.2 / playbackRate, {
				startDelay: Conductor.crochet * 0.001 / playbackRate,
				onComplete: (t) -> noteTimingRating.active = false
			});
		}

		if (!ClientPrefs.data.disableComboCounter) {
			var colorCombo:FlxColor = FlxColor.WHITE;
			if (ClientPrefs.data.colorRating) {
				if (songMisses == 0) {
					if (songShits > 0)
						colorCombo = COLOR_SHIT;
					else if (songBads > 0)
						colorCombo = COLOR_BAD;
					else if (songGoods > 0)
						colorCombo = COLOR_GOOD;
					else if (songSicks > 0)
						colorCombo = COLOR_SICK;
				} 
			}

			var seperatedScore:Array<Int> = [];

			if(combo >= 1000) {
				seperatedScore.push(Math.floor(combo / 1000) % 10);
			}
			seperatedScore.push(Math.floor(combo / 100) % 10);
			seperatedScore.push(Math.floor(combo / 10) % 10);
			seperatedScore.push(combo % 10);

			var daLoop:Int = 0;
			var xThing:Float = 0;
			if (lastScore != null)
			{
				while (lastScore.length > 0)
				{
					lastScore[0].kill();
					lastScore.remove(lastScore[0]);
				}
			}

			if(showComboNum)
				for (i in seperatedScore)
				{
					var numScore:FlxTweenedSprite = recycleComboSprite();
					numScore.loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
					numScore.cameras = [camHUD];
					numScore.screenCenter();
					numScore.x = placement[0] + (43 * daLoop) - 90 + getComboOffset(playsAsBF())[2];
					numScore.y += placement[1] + 80 - getComboOffset(playsAsBF())[3];
					
					if (!ClientPrefs.data.comboStacking)
						lastScore.push(numScore);

					if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
					else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
					numScore.updateHitbox();

					numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					numScore.velocity.y = -(FlxG.random.int(140, 160) * playbackRate);
					numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
					numScore.alpha = 1.0;
					numScore.visible = !ClientPrefs.data.hideHud;
					numScore.antialiasing = antialias;

					//if (combo >= 10 || combo == 0)
					comboGroup.remove(numScore, true);
					comboGroup.add(numScore);

					numScore.tween = FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
						onComplete: function(tween:FlxTween)
						{
							numScore.kill();
						},
						startDelay: Conductor.crochet * 0.002 / playbackRate
					});

					daLoop++;
					if(numScore.x > xThing) xThing = numScore.x;

					numScore.color = colorCombo;
				}
			if (comboSpr != null)
				comboSpr.x = xThing + 50;
		}

		return daRating;
	}

	public var strumsBlocked:Array<Bool> = [];
	
	inline private function onKeyPress(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if (!controls.controllerMode && FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
	}

	@:unreflective
	inline private function keyPressed(key:Int)
	{
		if (!checkCanInput())
			return;

		if (!cpuControlled && startedCountdown && !paused && key > -1)
		{
			if (notes.length > 0 && !self.stunned && generatedMusic && !endingSong)
			{
				//more accurate hit time for the ratings?
				var lastTime:Float = Conductor.songPosition;
				if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time;

				var canMiss:Bool = !ClientPrefs.getGhostTapping();

				// heavily based on my own code LOL if it aint broke dont fix it
				var pressNotes:Array<Note> = [];
				var notesStopped:Bool = false;
				var sortedNotesList:Array<Note> = [];
				notes.forEachAlive(function(daNote:Note)
				{
					if (strumsBlocked[daNote.noteData] != true && daNote.canBeHit && isPlayerNote(daNote) &&
						!daNote.tooLate && !daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
					{
						if(daNote.noteData == key) sortedNotesList.push(daNote);
						canMiss = true;
					}
				});
				sortedNotesList.sort(sortHitNotes);

				if (sortedNotesList.length > 0) {
					for (epicNote in sortedNotesList)
					{
						for (doubleNote in pressNotes) {
							if (Math.abs(doubleNote.strumTime - epicNote.strumTime) < 1) {
								//doubleNote.kill();
								notes.remove(doubleNote, true);
								doubleNote.destroy();
							} else
								notesStopped = true;
						}

						// eee jack detection before was not super good
						if (!notesStopped) {
							goodNoteHit(epicNote);
							pressNotes.push(epicNote);
						}

					}
				}
				else {
					callOnScripts('onGhostTap', [key]);
					if (canMiss && !self.stunned) noteMissPress(key);
				}

				// I dunno what you need this for but here you go
				//									- Shubs

				// Shubs, this is for the "Just the Two of Us" achievement lol
				//									- Shadow Mario
				if(!keysPressed.contains(key)) keysPressed.push(key);

				//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
				Conductor.songPosition = lastTime;
			}

			for (strumIndex in 0...strumLines.members.length) {
				var strum:StrumLine = getPlayerStrums(strumIndex);
				if (strum != null) {
					var spr:StrumNote = strum.members[key];
					if(strumsBlocked[key] != true && spr != null && spr?.animation?.curAnim?.name != 'confirm')
					{
						GameClient.send("strumPlay", ["pressed", key, 0, strumIndex]);
						spr.playAnim('pressed');
						spr.resetAnim = 0;
					}
				}
			}
			callOnScripts('onKeyPress', [key]);
		}
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	inline private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		//trace('Pressed: ' + eventKey);

		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	@:unreflective
	inline private function keyReleased(key:Int)
	{
		if (!checkCanInput())
			return;

		if(!cpuControlled && startedCountdown && !paused)
		{
			for (strumIndex in 0...strumLines.members.length) {
				var strum:StrumLine = getPlayerStrums(strumIndex);
				if (strum != null) {
					var spr:StrumNote = strum.members[key];
					if(spr != null)
					{
						GameClient.send("strumPlay", ["static", key, 0, strumIndex]);
						spr.playAnim('static');
						spr.resetAnim = 0;
					}
				}
			}
			callOnScripts('onKeyRelease', [key]);
		}
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				if (note == null)
					continue;

				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	inline private function onButtonPress(button:MobileButton, ids:Array<String>, unique:Int):Void
	{
		if (controls.mobileControls && ids.filter(id -> id.startsWith("NOTE")).length > 0 || ids.filter(id -> id.startsWith(Note.maniaKeys + "K_NOTE")).length > 0)
		{
			var buttonCode:Int = (unique == -1 ? 0 : unique);

			callOnScripts('onButtonPressPre', [buttonCode]);
			if (button.justPressed) keyPressed(buttonCode);
			callOnScripts('onButtonPress', [buttonCode]);
		}
	}

	inline private function onButtonRelease(button:MobileButton, ids:Array<String>, unique:Int):Void
	{
		if (controls.mobileControls && ids.filter(id -> id.startsWith("NOTE")).length > 0 || ids.filter(id -> id.startsWith(Note.maniaKeys + "K_NOTE")).length > 0)
		{
			var buttonCode:Int = (unique == -1 ? 0 : unique);

			callOnScripts('onButtonReleasePre', [buttonCode]);
			if(buttonCode > -1) keyReleased(buttonCode);
			callOnScripts('onButtonRelease', [buttonCode]);
		}
	}

	// Hold notes
	@:unreflective
	private inline function keysCheck():Void
	{
		if (!checkCanInput())
			return;

		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in keysArray)
		{
			holdArray.push(controls.pressed(key));
			pressArray.push(controls.justPressed(key));
			releaseArray.push(controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !self.stunned && generatedMusic)
		{
			// rewritten inputs???
			if(notes.length > 0)
			{
				notes.forEachAlive(function(daNote:Note)
				{
					// hold note functions
					if (strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && holdArray[daNote.noteData] && daNote.canBeHit
					&& isPlayerNote(daNote) && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit) {
						goodNoteHit(daNote);
					}
				});
			}

			self.noteHold = holdArray.contains(true);
			
			if (!self.noteHold || endingSong)
				playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else checkForAchievement(['oversinging']);
			#end

			// if (self.noteHold && !endingSong) {
			// 	#if ACHIEVEMENTS_ALLOWED
			// 	checkForAchievement(['oversinging']);
			// 	#end
			// } else if (self.animation.curAnim != null
			// 		&& self.holdTimer > Conductor.stepCrochet * (0.0011 / playbackRate) * self.singDuration
			// 		&& self.animation.curAnim.name.startsWith('sing')
			// 		&& !(self.animation.curAnim.name.endsWith('miss') || self.isMissing))
			// {
			// 	self.dance();
			// 	//boyfriend.animation.curAnim.finish();
			// }
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && isPlayerNote(daNote) && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1) {
				//note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		});

		final end:Note = daNote.isSustainNote ? daNote.parent.tail[daNote.parent.tail.length - 1] : daNote.tail[daNote.tail.length - 1];
		if (end != null && end.noteHoldSplash != null) {
			end.noteHoldSplash.kill();
		}
		
		noteMissCommon(daNote.noteData, daNote);
		stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote));
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote, getCharPlayTag(daNote.mustPress, GameClient.room?.sessionId ?? null)]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('noteMiss', [daNote, getCharPlayTag(daNote.mustPress, GameClient.room?.sessionId ?? null)]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.getGhostTapping()) return; //fuck it

		noteMissCommon(direction);
		stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction));
		callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// am i the only one that kinda hears the rayman 3 selection sound there
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), 0.3);

		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;
		subsHealth(subtract * healthLoss);

		if(instakillOnMiss)
		{
			getPlayerVocals().volume = 0;
			doDeathCheck(true);
		}
		combo = 0;

		if(!practiceMode) {
			songScore -= 10;
			GameClient.send("addScore", -10);
		}
		if(!endingSong) {
			songMisses++;
			GameClient.send("addMiss");
		}
		totalPlayed++;
		updateScoreSelf(true);
		// RecalculateRating(true);
		if (note != null)
			GameClient.send("noteMiss", [note.strumTime, note.noteData, note.isSustainNote]);

		// play character anims
		var charArray:Array<Character> = [self];
		var isGfMiss = (SONG.notes[curSection] != null && (SONG.notes[curSection].mustHitSection ? playsAsBF() : !playsAsBF()) && SONG.notes[curSection].gfSection) || (note != null && note.gfNote);

		if (isGfMiss) {
			charArray = [gf];
		} else {
			if (note != null) {
				var strumIdx:Int = getStrumFromNote(note);
				charArray = strumLines.members[strumIdx].characters.copy();
				
				// --- SID CHECK FOR MISSING A NOTE ---
				var mySid:String = GameClient.room?.sessionId;
				if (mySid != null && characters.exists(mySid) && (strumIdx == 0 || strumIdx == 1)) {
					charArray[0] = characters.get(mySid);
				}
			} else {
				// --- SID CHECK FOR GHOST TAPPING MISS ---
				var mySid:String = GameClient.room?.sessionId;
				if (mySid != null && characters.exists(mySid)) {
					charArray = [characters.get(mySid)];
				}
			}
		}

		for (char in charArray) {
			if(char != null && !(GameClient.isConnected() && char == gf && GameClient.getPlayerSelf().ox != 0) /*&& char.hasMissAnimations*/)
			{
				var suffix:String = '';
				if(note != null) suffix = note.animSuffix;

				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + suffix;
				char.playAnim(animToPlay, true);
				
				// Safely get strum index, default to 1 (player side) if ghost tapping
				var sIdx:Int = note != null ? getStrumFromNote(note) : 1; 
				GameClient.send("charPlay", [animToPlay, char == gf, false, sIdx]);

				if(char != gf && combo > 5 && gf != null && gf.animOffsets.exists('sad'))
				{
					gf.playAnim('sad');
					gf.specialAnim = true;
				}
			}
		}

		getPlayerVocals().volume = 0;
	}

	function countOpponents() {
		if (!GameClient.isConnected() || playOtherSide || GameClient.room.state.royalMode)
			return 1;

		var count = 0;
		for (character in characters) {
			if (!character.isPlayer) {
				count++;
			}
		}
		return count;
	}

	var opponentPopScore:Bool = false;
	var opponentNoteHits:Int = 0;

	function opponentNoteHit(note:Note, ?sid:String):Void
	{
		opponentNoteHits++;
		note.hits++;

		if (note.hits - countOpponents() > 0) {
			return;
		}

		var opChar = sid != null ? characters.get(sid) : getOpponent();

		var noteDiffNoAbs:Float = note.strumTime - (Conductor.judgeSongPosition ?? Conductor.songPosition) + ClientPrefs.getRatingOffset();
		var noteDiff:Float = Math.abs(noteDiffNoAbs);
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / (Conductor.judgePlaybackRate ?? playbackRate));
		if (opponentPopScore && !GameClient.isConnected()) {
			popUpScoreOP(daRating.image);
		}

		if (note.noteType == 'Hey!' && opChar.animOffsets.exists('hey')) {
			opChar.playAnim('hey', true);
			opChar.specialAnim = true;
			opChar.heyTimer = 0.6;
		} else if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (playsAsBF()) {
				if (SONG.notes[curSection] != null)
				{
					if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection) {
						altAnim = '-alt';
					}
				}
			}

			var charArray:Array<Character> = [opChar];
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + altAnim;
			
			if (note != null) {
				var strumIdx:Int = getStrumFromNote(note);
				
				if (note.gfNote) {
					charArray = [gf];
				} else {
					charArray = strumLines.members[strumIdx].characters.copy();
					
					// --- SID CHECK FOR OPPONENT ---
					if (sid != null && characters.exists(sid) && (strumIdx == 0 || strumIdx == 1)) {
						charArray[0] = opChar;
					}
				}
			}

			for (char in charArray) {
				if(char != null && !(GameClient.isConnected() && char == gf && sid != null && playersStats.get(sid).player.ox != 0))
				{
					char.playAnim(animToPlay, true);
					char.holdTimer = 0;
				}
			}
		}

		if (SONG.needsVoices) {
			if (sid != null)
				getVocalsFromSIDVolume(sid, 1);
			else
				getOpponentVocals().volume = 1;
		}

		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate, sid, note);
		note.hitByOpponent = true;

		var compat:String = note.mustPress ? 'goodNoteHit' : 'opponentNoteHit';
		var compatCNE:String = note.mustPress ? 'onPlayerHit' : 'onDadHit';
		var event:NoteHitEvent;
		var strumLine = strumLines.members[getStrumFromNote(note)];

		event = scripts.event(compatCNE, EventManager.get(NoteHitEvent).recycle(false, !note.isSustainNote, !note.isSustainNote, note, strumLine.characters, true, note.noteType, note.noteData, songScore, note.isSustainNote ? null : ratingPercent, 0.023, daRating.name));
		strumLine.onHit.dispatch(event);
		scripts.event("onNoteHit", event);
		if (event.enableCamZooming && Paths.formatToSongPath(SONG.song) != 'tutorial') camZooming = true;

		if (compat == 'goodNoteHit')
			stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note));
		else
			stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note));
		var result:Dynamic = callOnLuas(compat, [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote, getCharPlayTag(note.mustPress, sid)]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript(compat, [note, getCharPlayTag(note.mustPress, sid)]);	

		spawnHoldSplashOnNote(note);

		if (!note.isSustainNote)
		{
			//note.kill();
			notes.remove(note, true);
			note.destroy();
		}
	}

	function goodNoteHit(note:Note):Void
	{
		if(note.wasGoodHit || (cpuControlled && (note.ignoreNote || note.hitCausesMiss))) return;

		note.wasGoodHit = true;
		if (ClientPrefs.data.hitsoundVolume > 0 && !note.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(note.hitsound), ClientPrefs.data.hitsoundVolume);

		var charArray:Array<Character> = [self];
		if (note != null) {
			var strumIdx:Int = getStrumFromNote(note);
			charArray = strumLines.members[strumIdx].characters.copy();

			// --- SID CHECK FOR OUR PLAYER ---
			var mySid:String = GameClient.room?.sessionId;
			if (mySid != null && characters.exists(mySid) && (strumIdx == 0 || strumIdx == 1)) {
				charArray[0] = characters.get(mySid);
			}
		}

		if(note.hitCausesMiss) {
			noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote)
				spawnNoteSplashOnNote(note);

			if(!note.noMissAnimation)
			{
				switch(note.noteType) {
					case 'Hurt Note': //Hurt note
						for (charSelf in charArray) {
							if (charSelf.animation.getByName('hurt') != null) {
								charSelf.playAnim('hurt', true);
								charSelf.specialAnim = true;
							}
						}
				}
			}

			if (!note.isSustainNote)
			{
				//note.kill();
				notes.remove(note, true);
				note.destroy();
			}
			return;
		}

		var rating:Rating = null;
		if (!note.isSustainNote)
		{
			combo++;
			if(combo > 9999) combo = 9999;
			rating = popUpScore(note);

			switch (rating.name) {
				case "sick":
					addHealth(note.hitHealth * healthGain);
				case "good":
					addHealth((note.hitHealth * 0.5) * healthGain);
				case "bad":
					addHealth((note.hitHealth * 0.2) * healthGain);
			}
		}
		else {
			addHealth(note.hitHealth * healthGain);
		}

		// TODO: make it only provide the note.strumTime and Conductor.songPosition
		GameClient.send("noteHit", [note.strumTime, note.noteData, note.isSustainNote, rating?.image, note.noteType, notes.members.indexOf(note), note.mustPress]);
		GameClient.send("updateMaxCombo", maxCombo);

		if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (!playsAsBF()) {
				if (SONG.notes[curSection] != null) {
					if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection) {
						altAnim = '-alt';
					}
				}
			}

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, note.noteData)))] + altAnim;

			var char:Character = self;
			var animCheck:String = 'hey';
			
			if(note.gfNote)
			{
				char = gf;
				animCheck = 'cheer';
			}

			if (note != null) {
				var strumIdx:Int = getStrumFromNote(note);
				
				if (note.gfNote) {
					charArray = [gf];
				} else {
					charArray = strumLines.members[strumIdx].characters.copy();

					var mySid:String = GameClient.room?.sessionId;
					if (mySid != null && characters.exists(mySid) && (strumIdx == 0 || strumIdx == 1)) {
						charArray[0] = characters.get(mySid);
					}
				}
			}

			for (char in charArray) {
				if(char != null && !(GameClient.isConnected() && char == gf && GameClient.getPlayerSelf().ox != 0))
				{
					char.playAnim(animToPlay, true);
					char.holdTimer = 0;

					if (note.noteType == 'Hey!' && char.animOffsets.exists(animCheck)) {
						char.playAnim(animCheck, true);
						char.specialAnim = true;
						char.heyTimer = 0.6;
						GameClient.send("charPlay", [animCheck, note.gfNote, true, getStrumFromNote(note)]);
					} else {
						GameClient.send("charPlay", [animToPlay, note.gfNote, false, getStrumFromNote(note)]);
					}
				}
			}
		}

		if(!cpuControlled)
		{
			var spr = strumLines.members[getStrumFromNote(note)].members[note.noteData];
			GameClient.send("strumPlay", ["confirm", note.noteData, 0, getStrumFromNote(note)]);
			if(spr != null) spr.playAnim('confirm', true);
		}
		else {
			strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate, null, note);
		}
		getPlayerVocals().volume = 1;

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		var compat:String = note.mustPress ? 'goodNoteHit' : 'opponentNoteHit';
		var compatCNE:String = note.mustPress ? 'onPlayerHit' : 'onDadHit';
		var event:NoteHitEvent;
		var strumLine = strumLines.members[getStrumFromNote(note)];

		var noteDiffNoAbs:Float = note.strumTime - (Conductor.judgeSongPosition ?? Conductor.songPosition) + ClientPrefs.getRatingOffset();
		var noteDiff:Float = Math.abs(noteDiffNoAbs);
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / (Conductor.judgePlaybackRate ?? playbackRate));
		event = scripts.event(compatCNE, EventManager.get(NoteHitEvent).recycle(false, !note.isSustainNote, !note.isSustainNote, note, strumLine.characters, true, note.noteType, note.noteData, songScore, note.isSustainNote ? null : ratingPercent, 0.023, daRating.name));
		strumLine.onHit.dispatch(event);
		scripts.event("onNoteHit", event);
		if (event.enableCamZooming && Paths.formatToSongPath(SONG.song) != 'tutorial') camZooming = true;

		if (compat == 'goodNoteHit')
			stagesFunc(function(stage:BaseStage) stage.goodNoteHit(note));
		else
			stagesFunc(function(stage:BaseStage) stage.opponentNoteHit(note));
		var result:Dynamic = callOnLuas(compat, [notes.members.indexOf(note), leData, leType, isSus, getCharPlayTag(note.mustPress, GameClient.room?.sessionId ?? null)]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript(compat, [note, getCharPlayTag(note.mustPress, GameClient.room?.sessionId ?? null)]);

		spawnHoldSplashOnNote(note);

		if (!note.isSustainNote)
		{
			note.kill();
			notes.remove(note, true);
			note.destroy();
		}
	}

	public function spawnHoldSplashOnNote(note:Note) {
		if (ClientPrefs.data.holdSplashAlpha <= 0)
			return;

		if (note != null) {
			var strum:StrumNote = strumLines.members[getStrumFromNote(note)].members[note.noteData];

			if(strum != null && note.tail.length != 0)
				spawnHoldSplash(note);
		}
	}

	public function spawnHoldSplash(note:Note) {
		var end:Note = note.isSustainNote ? note.parent.tail[note.parent.tail.length - 1] : note.tail[note.tail.length - 1];
		var splash:SustainSplash = grpHoldSplashes.recycle(SustainSplash);
		var strum:StrumNote = strumLines.members[getStrumFromNote(note)].members[note.noteData];

		splash.setupSusSplash(strum, note, playbackRate);
		#if HSC_ALLOWED scripts.call("onSpawnHoldSplash", [splash, strum, note]); #end //for changing cameras
		grpHoldSplashes.add(end.noteHoldSplash = splash);
	}

	// Backwards compatibility.
	public inline function getStrumFromNote(note:Note) {
		return note.strumLineID;
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if (ClientPrefs.data.splashAlpha <= 0)
			return;

		if(note != null) {
			var strum:StrumNote = strumLines.members[getStrumFromNote(note)].members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x - (Note.swagWidth - Note.swagScaledWidth), strum.y - (Note.swagWidth - Note.swagScaledWidth), note.noteData, note, strum);
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null, ?strumNote:StrumNote) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		#if HSC_ALLOWED scripts.call("onSpawnNoteSplash", [splash, x, y, data, note, strumNote]); #end //for changing cameras
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		#if HSC_ALLOWED scripts.call("destroy"); #end
		#if LUA_ALLOWED
		for (i in 0...luaArray.length) {
			var lua:FunkinLua = luaArray[0];
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				script.call('onDestroy');
				script.destroy();
			}

		while (hscriptArray.length > 0)
			hscriptArray.pop();
		#end

		#if HSC_ALLOWED
		scripts = FlxDestroyUtil.destroy(scripts);
		#end

		//destroy manager
		for (managerName => manager in customManagers)
			manager[0].destroy();

		stagesFunc(function(stage:BaseStage) stage.destroy());

		#if VIDEOS_ALLOWED
		if(videoCutscene != null)
		{
			videoCutscene.destroy();
			videoCutscene = null;
		}
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		FlxG.camera.setFilters([]);

		FlxG.animationTimeScale = 1;
		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end

		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();

		instance = null;
		orderOffset = 0;
		// if (stage3D != null) {
		// 	Main.backSprite.removeChild(stage3D);
		// 	//stage3D.dispose();
		// 	stage3D = null;
		// }
		super.destroy();
		//
		// great haxeflixel
		//
		// if (!FlxG.fullscreen) {
		// 	if (Lib.application.window.width != FlxG.width) {
		// 		Lib.application.window.x += Std.int((Lib.application.window.width - FlxG.width) / 2);
		// 		Lib.application.window.width = FlxG.width;
		// 	}
		// 	if (Lib.application.window.height != FlxG.height) {
		// 		Lib.application.window.y += Std.int((Lib.application.window.height - FlxG.height) / 2);
		// 		Lib.application.window.height = FlxG.height;
		// 	}
		// }
		// Lib.application.window.resizable = true;
		Lib.application.window.title = "Friday Night Funkin': Psych Extended Online" + (states.TitleState.inDev ? ' [DEV]' : '');
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
	}

	public static function cancelMusicFadeTween() {
		if(FlxG.sound.music.fadeTween != null) {
			FlxG.sound.music.fadeTween.cancel();
		}
		FlxG.sound.music.fadeTween = null;
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		if (!isCreated) {
			return;
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		if (!GameClient.isConnected() && swingMode && (curStep % 4 == 3)) { // here in the funkin crew we call that a functional audio resyncing algorithm
			setSongTime(Conductor.songPosition + Conductor.calculateCrochet(Conductor.bpm) / 4);
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
		#if HSC_ALLOWED scripts.call("stepHit", [curStep]); #end
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if (!isCreated) {
			return;
		}

		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		// if (generatedMusic)
		// 	notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		for (icon in iconP1s.concat(iconP2s)) {
			icon.scale.x = iconZoomIntensity * iconSizeMult((icon.isPlayer ? iconP1s : iconP2s));
			icon.scale.y = icon.scale.x;
			icon.updateHitbox();
		}

		characterBopper(curBeat);

		if (camZoomingInterval < 1) camZoomingInterval = 1;
		if (ClientPrefs.data.alterCamera && camZooming && FlxG.camera.zoom < maxCamZoom && curBeat % camZoomingInterval == 0)
		{
			FlxG.camera.zoom += 0.015 * camZoomingStrength;
			camHUD.zoom += 0.03 * camZoomingStrength;
		}
		else if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms && cameraZoomRate != 0 && curBeat % cameraZoomRate == 0)
		{
			FlxG.camera.zoom += (0.015 * camZoomingMult) * cameraBopIntensity * defaultCamZoom;
			camHUD.zoom += (hudCameraZoomIntensity * camZoomingMult) * defaultHUDCamZoom;
		}

		//if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
		// {
		// 	FlxG.camera.zoom += 0.015 * camZoomingMult;
		// 	camHUD.zoom += 0.03 * camZoomingMult;
		// }

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
		#if HSC_ALLOWED
		if (scripts != null) scripts.call('beatHit', [curBeat]); //why not
		#end
	}

	public function characterBopper(beat:Int):Void {
		if (gf != null) {
			if (gf.danceEveryNumBeats != 0 && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && gf.animation.curAnim != null && !gf.animation.curAnim.name.startsWith("sing") && !gf.stunned)
				gf.dance();

			if (gf?.speaker is Character) {
				final speaker:Character = cast gf.speaker;
				if (speaker.danceEveryNumBeats != 0 && beat % Math.round(gfSpeed * speaker.danceEveryNumBeats) == 0)
					speaker.dance();
			}
		}

		//idle support to extra chars
		for (strumIndex in 0...strumLines.members.length) {
			var chars:Array<Character> = strumLines.members[strumIndex].characters;
			for (char in chars) {
				if (char != null) {
					if (char.lastHit + (Conductor.stepCrochet * char.singDuration) < Conductor.songPosition && char.codenameOffsets)
						char.dance();

					if (char.danceEveryNumBeats != 0 && beat % char.danceEveryNumBeats == 0 && char.animation.curAnim != null && !char.animation.curAnim.name.startsWith('sing') && !char.stunned && char != gf && !char.codenameOffsets)
						char.dance();
				}
			}
		}

		onlineCharacterBopper(beat);
	}

	function onlineCharacterBopper(beat:Int) {
		if (!GameClient.isConnected())
			return;

		for (character in characters) {
			if (isCharacterPlayer(character) || character == null)
				continue;

			var isSinging:Bool = character.animation.curAnim != null && character.animation.curAnim.name.startsWith('sing');
			var isMissing:Bool = character.animation.curAnim != null && (character.animation.curAnim.name.endsWith('miss') || character.isMissing);

			if (isSinging && !isMissing && !character.stunned) {
				var holdTimerExpired:Bool = character.holdTimer > Conductor.stepCrochet * (0.0011 / playbackRate) * character.singDuration;
				if (character.codenameOffsets)
					holdTimerExpired = (character.lastHit + (Conductor.stepCrochet * character.singDuration) < Conductor.songPosition);
				
				if (holdTimerExpired && (!character.noteHold || endingSong)) {
					character.dance();
				}
			}

			// Re-check singing status because the step above might have just made them stop singing!
			isSinging = character.animation.curAnim != null && character.animation.curAnim.name.startsWith('sing');

			if (character.danceEveryNumBeats != 0 
				&& beat % character.danceEveryNumBeats == 0 
				&& !isSinging 
				&& !character.stunned && !character.codenameOffsets) 
			{
				character.dance();
			}
		}
	}

	public function playerDance():Void {
		var anim:String = self.getAnimationName();
		if (self.lastHit + (Conductor.stepCrochet * self.singDuration) < Conductor.songPosition && self.codenameOffsets && anim.startsWith('sing') && !anim.endsWith('miss'))
		{
			self.dance();
			self.noteHold = false;
		}
		if(self.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * self.singDuration && anim.startsWith('sing') && !anim.endsWith('miss') && !self.codenameOffsets)
		{
			self.dance();
			self.noteHold = false;
		}
	}

	override function sectionHit()
	{	
		if (!isCreated) {
			return;
		}

		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos && !ClientPrefs.data.alterCamera)
				moveCameraSection();

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		if (gf?.speaker is ABotSpeaker)
			cast(gf.speaker, ABotSpeaker).updateABotEye(cameraLookAt);
		
		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FunkinFileSystem.exists(luaToLoad))
			luaToLoad = Paths.getPreloadPath(luaFile);

		if(FunkinFileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getPreloadPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;
	
			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end
	
	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String, ?useImproved:Bool)
	{
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FunkinFileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getPreloadPath(scriptFile);
		
		if(FunkinFileSystem.exists(scriptToLoad))
		{
			if (SScript.global.exists(scriptToLoad)) return false;

			#if HSC_ALLOWED if (useImproved) addScript(scriptToLoad);
			else #end initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function findAndStartScripts(scriptFolder:String, ?onlyUseImproved:Bool)
	{
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), '${scriptFolder}/');

		for (folder in foldersToCheck)
			for (file in FunkinFileSystem.readDirectory(folder))
			{
				if(file.toLowerCase().endsWith('.lua') && !onlyUseImproved)
					new FunkinLua(folder + file);
				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx') && !onlyUseImproved)
					initHScript(folder + file);
				#end
				#if HSC_ALLOWED
				if(file.toLowerCase().endsWith('.hsc'))
					addScript(folder + file);
				#end
			}
	}

	public function initHScript(file:String):HScript
	{
		var newScript:HScript;
		try
		{
			newScript = new HScript(null, file);
			@:privateAccess
			if(newScript.parsingException != null)
			{
				addTextToDebug('ERROR ON LOADING: ${newScript.parsingException.message}', FlxColor.RED);
				newScript.destroy();
				return null;
			}

			hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
						if (e != null)
							addTextToDebug('ERROR ($file: onCreate) - ${e.message.substr(0, e.message.indexOf('\n'))}', FlxColor.RED);

					newScript.destroy();
					hscriptArray.remove(newScript);
					if (ClientPrefs.isDebug())
						trace('failed to initialize sscript interp!!! ($file)');
				}
				else if (ClientPrefs.isDebug()) trace('initialized sscript interp successfully: $file');
			}
			
		}
		catch(e)
		{
			addTextToDebug('ERROR ($file) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
			newScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				hscriptArray.remove(newScript);
			}
			return null;
		}
		return newScript;
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [psychlua.FunkinLua.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = FunkinLua.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [FunkinLua.Function_Continue];

		var len:Int = luaArray.length;
		var i:Int = 0;
		while(i < len)
		{
			var script:FunkinLua = luaArray[i];
			if (script == null) {
				luaArray.remove(script);
				i++;
				continue;
			}

			if(exclusions.contains(script.scriptName))
			{
				i++;
				continue;
			}

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == FunkinLua.Function_StopLua || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}
			
			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(!script.closed) i++;
			else len--;
		}
		#end
		return returnVal;
	}
	
	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		#if HSC_ALLOWED
		var cneLikeFunctions = funcToCall;
		var doNotCall:Bool = false;
		if (funcToCall == 'onCreatePost') cneLikeFunctions = 'postCreate';
		else if (funcToCall == 'onSongStart') doNotCall = true;
		else if (funcToCall == 'onStartCountdown') doNotCall = true;

		if (scripts != null && !doNotCall) scripts.call(cneLikeFunctions, args);
		#end

		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(psychlua.FunkinLua.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len)
		{
			var script:HScript = hscriptArray[i];
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try
			{
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
						FunkinLua.trace('ERROR (${script.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), true, false, FlxColor.RED);
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == FunkinLua.Function_StopHScript || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}
					
					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSC_ALLOWED if (scripts != null) scripts.set(variable, arg); #end
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	#if HSC_ALLOWED
	public function addScript(file:String) {
		//trace('addScript: ${file}');
		var ext = Path.extension(file).toLowerCase();
		if (Script.scriptExtensions.contains(ext))
		{
			scripts.add(Script.create(file));
		}
	}
	#end

	function strumPlayAnim(isDad:Bool, id:Int, time:Float, ?sid:String, note:Note) {
		var spr:StrumNote = null;
		var strumIndex = getStrumFromNote(note);
		var strums = isDad ? getOpponentStrums(strumIndex) : getPlayerStrums(strumIndex);

		if (sid != null && (strumIndex == 0 || strumIndex == 1)) {
			strums = getStrumsFromSID(sid);
			if (isDad && strums == getPlayerStrums())
				return;
		}
		if(isDad) {
			spr = strums.members[id];
		} else {
			spr = strums.members[id];
			GameClient.send("strumPlay", ["confirm", id, time, strumIndex]);
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent(default, null):Float;
	public var ratingFC:String;
	//WHY IS THIS IN UPPERCASE
	public function RecalculateRating(badHit:Bool = false) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != FunkinLua.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = Language.getText(ratingStuff[ratingStuff.length-1][0]); //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = Language.getText(ratingStuff[i][0]);
							break;
						}
			}
			fullComboFunction();
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce -Ghost
	}

	function fullComboUpdate()
	{
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;

		ratingFC = 'Clear';
		if(songMisses < 1)
		{
			if (shits > 0) ratingFC = 'NM';
			else if (bads > 0) ratingFC = 'FC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
		}
		else if (songMisses < 10)
			ratingFC = 'SDCB'; // what the fuck is SDCB
	}

	#if ACHIEVEMENTS_ALLOWED
	inline private function checkForAchievement(achievesToCheck:Array<String> = null)
	{
		if(chartingMode || isInvalidScore()) return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));

		for (name in achievesToCheck) {
			if(!Achievements.exists(name)) continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch(name)
				{
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (/*!ClientPrefs.data.cacheOnGPU && */!ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					#if BASE_GAME_FILES
					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
					#end

					case '1000combo':
						unlock = combo > 1000;
				}
			}
			else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
					unlock = true;
			}

			if(unlock) Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	public function createRuntimeShader(name:String):FlxRuntimeShader
	{
		if(!ClientPrefs.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!runtimeShaders.exists(name) && !initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		var arr:Array<String> = runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));

		for(mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));
		
		for (folder in foldersToCheck)
		{
			if(FunkinFileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if(FunkinFileSystem.exists(frag))
				{
					frag = FunkinFileSystem.getText(frag);
					found = true;
				}
				else frag = null;

				if(FunkinFileSystem.exists(vert))
				{
					vert = FunkinFileSystem.getText(vert);
					found = true;
				}
				else vert = null;

				if(found)
				{
					runtimeShaders.set(name, [frag, vert]);
					//trace('Found shader $name!');
					return true;
				}
			}
		}
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}
	#end

	var isDuel:Bool = true;
	public var opponentPlayer:Player;

	var forceInvalidScore = false;
	function isInvalidScore() {
		return cpuControlled || controls.moodyBlues != null || noBadNotes || forceInvalidScore;
	}

	// MULTIPLAYER STUFF HERE

	public function addHealth(v:Float) {
		if (!PlayState.playsAsBF()) {
			return health -= v;
		}
		return health += v;
	}

	public function subsHealth(v:Float) {
		if (!PlayState.playsAsBF()) {
			return health += v;
		}
		return health -= v;
	}

	public static function playsAsBF() {
		if (GameClient.isConnected()) {
			if (GameClient.room.state.royalMode) {
				return !GameClient.room.state.royalModeDadSide;
			}

			if (GameClient.getPlayerSelf() != null) {
				return GameClient.getPlayerSelf().bfSide;
			}
		}
		return !opponentMode;
	}

	public static function isPlayerNote(note:Note):Bool {
		return note.mustPress == playsAsBF();
	}

	public static function isPlayerStrumNote(player:Int):Bool {
		if (playsAsBF()) {
			return player == 1;
		}
		return player == 0;
	}

	public static function isCharacterPlayer(character:Character) {
		if (instance?.self == null) 
			return character.isPlayer;

		return character == instance.self;
	}

	public function getPlayerStrums(?strumIndex:Int = -1, ?cannotBeNull:Bool) {
		var selectedStrum:StrumLine = null;
		var strumLine:StrumLine = strumLines.members[strumIndex];
		if (playsAsBF()) {
			if (strumLine != null && !strumLine.cpu)
				selectedStrum = strumLine;

			if (selectedStrum == null && cannotBeNull) selectedStrum = playerStrums;
			return selectedStrum;
		}
		if (strumLine != null && strumLine.cpu)
			selectedStrum = strumLine;

		if (selectedStrum == null && cannotBeNull) selectedStrum = opponentStrums;
		return selectedStrum;
	}

	public function getOpponentStrums(?strumIndex:Int = -1, ?cannotBeNull:Bool) {
		var selectedStrum:StrumLine = null;
		var strumLine:StrumLine = strumLines.members[strumIndex];
		if (playsAsBF()) {
			if (strumLine != null && strumLine.cpu)
				selectedStrum = strumLine;

			if (selectedStrum == null) selectedStrum = opponentStrums;
			return selectedStrum;
		}
		if (strumLine != null && !strumLine.cpu)
			selectedStrum = strumLine;

		if (selectedStrum == null) selectedStrum = playerStrums;
		return selectedStrum;
	}

	public inline function getAllPlayerStrums():Array<StrumLine>
	{
		var strumList:Array<StrumLine> = [];
		for (strum in strumLines.members)
		{
			if (!strum.cpu && PlayState.playsAsBF()) strumList.push(strum);
			else if (strum.cpu && !PlayState.playsAsBF()) strumList.push(strum);
		}
		return strumList;
	}

	public function getStrumsFromSID(sid:String, ?strumIndex:Int = -1) {
		if (GameClient.isConnected() && GameClient.room.state.royalMode) {
			// TODO display note chart on seperate opponentStrums
			return GameClient.room.state.royalModeDadSide ? opponentStrums : playerStrums;
		}

		var selectedStrum:StrumLine = null;
		var strumLine:StrumLine = strumLines.members[strumIndex];
		if (characters.get(sid).isPlayer == playsAsBF()) {
			if (strumLine != null && !strumLine.cpu)
				selectedStrum = strumLine;

			if (selectedStrum == null) selectedStrum = playerStrums;
			return selectedStrum;
		}
		if (strumLine != null && strumLine.cpu)
			selectedStrum = strumLine;

		if (selectedStrum == null) selectedStrum = opponentStrums;
		return selectedStrum;
	}

	function get_self() {
		if (GameClient.isConnected() && GameClient.room != null) {
			return characters.get(GameClient.room.sessionId);
		}
		if (!playsAsBF()) {
			return dad;
		}
		return boyfriend;
	}

	public function getOpponent() {
		if (GameClient.isConnected() && GameClient.room.state.royalMode) {
			return isNulledBf ? boyfriend : isNulledDad ? dad : dummy;
			// return gf;
		}

		if (playsAsBF()) {
			return dad;
		}
		return boyfriend;
	}

	public function getPlayerVocals() {
		if (opponentVocals.length <= 0)
			return vocals;

		if (playsAsBF())
			return vocals;
		return opponentVocals;
	}

	public function getOpponentVocals() {
		if (opponentVocals.length <= 0)
			return vocals;

		if (playsAsBF())
			return opponentVocals;
		return vocals;
	}

	public function getVocalsFromSIDVolume(sid:String, v:Float) {
		final vocals = getVocalsFromSID(sid);
		if (vocals != null)
			vocals.volume = v;
	}

	public function getVocalsFromSID(sid:String) {
		if (GameClient.isConnected() && GameClient.room.state.royalMode) {
			return null;
		}

		if (opponentVocals.length <= 0 || characters.get(sid).isPlayer == playsAsBF()) {
			return vocals;
		}
		return opponentVocals;
	}

	function registerMessages() {
		GameClient.initStateListeners(this, this.registerMessages);

		if (!GameClient.isConnected())
			return;

		for (sid => player in GameClient.room.state.players) {
			GameClient.callbacks.listen(player, "ping", (value, prev) -> {
				Waiter.put(() -> {
					if (callOnScripts('onPlayerPing', [sid, player.ping], true) == FunkinLua.Function_Stop)
						return;
	
					updateScoreSID(sid, true);
					// if (player.bfSide == playsAsBF())
					// 	updateScore(false, true);
					// else
					// 	updateScoreOpponent(sid, false);
				});
			});

			GameClient.callbacks.listen(player, "botplay", (value, prev) -> {
				Waiter.put(() -> {
					if (callOnScripts('onPlayerBotplay', [sid, value], true) == FunkinLua.Function_Stop)
						return;
	
					showBotplay();
				});
			});

			GameClient.callbacks.listen(player, "noteHold", (value, prev) -> {
				Waiter.put(() -> {
					if (callOnScripts('onPlayerNoteHold', [sid, value], true) == FunkinLua.Function_Stop)
						return;

					if (characters.exists(sid))
						characters.get(sid).noteHold = value;
				});
			});
		}

		GameClient.room.onMessage("custom", function(message:Array<Dynamic>) {
			if (message.length != 2)
				return;

			Waiter.put(() -> {
				callOnScripts('onCustomMessage', message);
			});
		});

		GameClient.room.onMessage("log", function(message) {
			Waiter.putPersist(() -> {
				Alert.alert("New message", online.util.ShitUtil.parseLog(message).content);
			});
		});

		/**
		 * NOTE TO FUTURE MYSELF: this thing doesn't have seperated strum animation support yet, add it when mustPress shit is fixed.
		*/
		GameClient.room.onMessage("strumPlay", function(_message:Array<Dynamic>) {	  
			var sid:String = _message[0];
			var message:Array<Dynamic> = _message[1];

			// scrapped: make it so with tab you can switch to someone's else strum line

			Waiter.put(() -> {
				if (message == null || message[0] == null || message[1] == null || message[2] == null)
					return;

				if (callOnScripts('onMessageStrumPlay', [sid, message], true) == FunkinLua.Function_Stop)
					return;

				var strums = getStrumsFromSID(sid,message[3]);
				if (strums == getPlayerStrums(message[3])) {
					return;
				}
				var spr = strums.members[message[1]];
				if (spr != null) {
					spr.playAnim(message[0] + "", true);
					spr.resetAnim = message[2];
				}
			});
		});

		GameClient.room.onMessage("charPlay", function(_message:Array<Dynamic>) {
			var sid:String = _message[0];
			var message:Array<Dynamic> = _message[1];

			Waiter.put(() -> {
				if (message == null || message[0] == null)
					return;

				if (callOnScripts('onMessageCharPlay', [sid, message], true) == FunkinLua.Function_Stop)
					return;

				if (message[1] ?? false && gf != null) {
					gf.playAnim(message[0], true);
					if (message[2] ?? false)
						gf.specialAnim = true;
				} 
				else if (!(message[1] ?? false)) {
					var strumIdx:Int = message[3];
					var charArray:Array<Character> = [];

					if (strumLines.members[strumIdx] != null) {
						charArray = strumLines.members[strumIdx].characters.copy();
					}

					// Failsafe in case the strumline somehow had no characters
					if (charArray.length <= 0) {
						charArray.push(null);
					}

					// 2. --- SID CHECK ---
					if (characters.exists(sid) && (strumIdx == 0 || strumIdx == 1)) {
						charArray[0] = characters.get(sid);
					}

					for (char in charArray) {
						if (char == null) continue;

						char.playAnim(message[0], true);
						if (message[2] ?? false)
							char.specialAnim = true;
					}
				}
			});
		});

		GameClient.room.onMessage("noteHit", function(_message:Array<Dynamic>) {
			var sid:String = _message[0];
			var message:Array<Dynamic> = _message[1];

			Waiter.put(() -> {
				if (message == null || message[0] == null || message[1] == null || message[2] == null)
					return;

				if (callOnScripts('onMessageNoteHit', [sid, message], true) == FunkinLua.Function_Stop)
					return;

				notes.forEachAlive(function(note:Note) {
					if (!isPlayerNote(note)
						&& note.noteData == message[1]
						&& note.isSustainNote == message[2]
						&& Math.abs(note.strumTime - message[0]) < 1) 
					{
						opponentNoteHit(note, sid);
					}
				});

				if (!message[2] && message[3] != null) {
					getPlayerStats(sid).combo++;
					popUpScoreOP(message[3], sid);
				}

				callOnLuas(message[6] ? 'goodNoteHit' : 'opponentNoteHit', [message[5], message[1], message[4], message[2], getCharPlayTag(message[6], sid)]);
				callOnHScript(message[6] ? 'goodNoteHit' : 'opponentNoteHit', [notes.members[message[5]], getCharPlayTag(message[6], sid)]);
				// RecalculateRatingOpponent(sid, false);
				updateScoreSID(sid, false);
				getVocalsFromSIDVolume(sid, 1);
			});
		});

		GameClient.room.onMessage("noteMiss", function(_message:Array<Dynamic>) {
			var sid:String = _message[0];
			var message:Array<Dynamic> = _message[1];

			Waiter.put(() -> {
				if (message == null || message[0] == null || message[1] == null || message[2] == null)
					return;

				if (callOnScripts('onMessageNoteMiss', [sid, message], true) == FunkinLua.Function_Stop)
					return;

				notes.forEachAlive(function(note:Note) {
					if (!isPlayerNote(note)
						&& note.noteData == message[1]
						&& note.isSustainNote == message[2]
						&& Math.abs(note.strumTime - message[0]) < 1) 
					{
						//note.kill();
						unspawnNotes.remove(note);
						note.destroy();
					}
				});

				// RecalculateRatingOpponent(sid, true);
				updateScoreSID(sid, true);
				getVocalsFromSIDVolume(sid, 0);
				getPlayerStats(sid).combo = 0;
			});
		});

		GameClient.room.onMessage("startSong", function(_) {
			Waiter.put(() -> {
				if (callOnScripts('onMessageStartSong', null, true) == FunkinLua.Function_Stop)
					return;

				isReady = true;
				waitReady = false;
				startCountdown();
			});
		});

		GameClient.room.onMessage("endSong", function(_) {
			Waiter.put(() -> {
				if (callOnScripts('onMessageEndSong', null, true) == FunkinLua.Function_Stop)
					return;

				canEndSongOnline = true;
				endSong();
			});
		});

		ChatBox.tryRegisterLogs();
	}

	var playersStats:Map<String, PlayStatePlayer> = new Map<String, PlayStatePlayer>();

	public function updateScoreSelf(?miss:Bool = false) {
		RecalculateRating(miss);
		if (GameClient.isConnected()) {
			updateScoreSID(GameClient.room.sessionId);
		}
	}

	public function updateTeamSide(isRight:Bool, miss:Bool) {
		var sideNames = [];
		var sideScores = [];
		var sideMisses = [];
		var sideAccuracy = [];
		var sidePing = [];
		var sideFP = [];

		for (sid => player in GameClient.room.state.players) {
			if (player.bfSide == isRight) {
				var stats = getPlayerStats(sid);

				var ret:Dynamic = callOnScripts('onRecalculateRatingPlayer', [sid], true);
				if (ret != FunkinLua.Function_Stop) {
					stats.recalculateRating();
				}

				sideNames.push(player.name);
				sideScores.push(player.score);
				sideMisses.push(player.misses);
				sideAccuracy.push(stats.ratingPercent * 100);
				sidePing.push(player.ping);
				if (ClientPrefs.data.showFP) {
					sideFP.push(player.songPoints);
				}
			}
		}

		if (sideNames.length == 0)
			return;

		var daText = scoreTxtOthers.get(isRight ? 'RIGHTSIDE' : 'LEFTSIDE');

		daText.text = Language.getText('PlayState.updateTeamSide.daText', [
			sideNames.join(' & '),
			FlxStringUtil.formatMoney(averageOf(sideScores), false),
			averageOf(sideMisses),
			CoolUtil.floorDecimal(averageOf(sideAccuracy), 2),
			averageOf(sideFP),
			sidePing.join('ms & ')
		]);
		daText.y = scoreTxtOriginY - daText.height;

		if (!miss) {
			doTweenScore(isRight ? 'RIGHTSIDE' : 'LEFTSIDE', isRight);
		}

		callOnScripts('onUpdateScoreTeam', [isRight, miss]);
	}

	function averageOf(arr:Array<Float>):Float {
		if (arr.length == 0)
			return 0;
		var sum = 0.0;
		for (item in arr)
			sum += item;
		if (sum == 0)
			return 0;
		return sum / arr.length;
	}

	public function updateScoreSID(sid:String, ?miss:Bool = false) {
		var op = getPlayerStats(sid);

		if (GameClient.room.state.teamMode) {
			updateTeamSide(op.player.bfSide, miss);
			return;
		}

		setOnScripts('scoreOP', op.player.score);
		setOnScripts('missesOP', op.player.misses);
		setOnScripts('hitsOP', op.calcHits()); // may be inaccurate to hits
		setOnScripts('comboOP', op.combo);

		var ret:Dynamic = callOnScripts('onRecalculateRatingPlayer', [sid], true);
		if (ret != FunkinLua.Function_Stop) {
			op.recalculateRating();
		}

		var str:String = op.ratingName ?? '?';
		var percent:Float = 0;
		if (op.calcTotalPlayed() != 0) {
			percent = CoolUtil.floorDecimal(op.ratingPercent * 100, 2);
			str += ' ($percent%) - ${op.ratingFC}';
		}

		var countSide = 0;
		for (sid => player in GameClient.room.state.players) {
			if (player.bfSide == op.player.bfSide) {
				countSide++;
			}
		}

		var daText = scoreTxtOthers.get(sid);

		if (countSide > 1) {
			daText.text = Language.getText('PlayState.updateScoreSID.if (countSide > 1).daText', [
				op.player.name,
				FlxStringUtil.formatMoney(op.player.score, false),
				op.player.misses,
				percent,
				op.ratingFC,
				op.player.songPoints,
				op.player.ping
			]);
		}
		else {
			daText.text = Language.getText('PlayState.updateScoreSID.else.daText', [
				op.player.name,
				FlxStringUtil.formatMoney(op.player.score, false),
				op.player.misses,
				str,
				op.player.songPoints,
				op.player.ping
			]);
		}

		daText.y = scoreTxtOriginY - (op.player.ox * 20) - daText.height;

		if (!miss) {
			doTweenScore(sid);
		}

		setOnScripts('ratingOP', op.ratingPercent);
		setOnScripts('ratingNameOP', op.ratingName);
		setOnScripts('ratingFCOP', op.ratingFC);

		callOnScripts('onUpdateScorePlayer', [sid, miss]);
	}

	function doTweenScore(sid:String, ?isRight:Null<Bool> = null) {
		if (isRight != null) {
			sid = isRight ? 'RIGHTSIDE' : 'LEFTSIDE';
		}

		if (ClientPrefs.data.scoreZoom) {
			if (scoreTxtOthersTween.exists(sid)) {
				scoreTxtOthersTween.get(sid).cancel();
			}

			var text = scoreTxtOthers.get(sid);
			text.scale.x = 1.025;
			text.scale.y = 1.025;
			
			scoreTxtOthersTween.set(sid, FlxTween.tween(text.scale, {x: 1, y: 1}, 0.2, {
				onComplete: function(twn:FlxTween) {
					scoreTxtOthersTween.remove(sid);
				}
			}));
		}
	}

	function getPlayerStats(sid:String) {
		if (!playersStats.exists(sid))
			playersStats.set(sid, new PlayStatePlayer(GameClient.room.state.players.get(sid)));

		return playersStats.get(sid);
	}

	public var scrollXCenter(get, set):Float;
	function get_scrollXCenter() {
		return camGame.scroll.x - FlxG.width / 2;
	}
	function set_scrollXCenter(value) {
		return camGame.scroll.x = value - FlxG.width / 2;
	}

	public var scrollYCenter(get, set):Float;
	function get_scrollYCenter() {
		return camGame.scroll.y - FlxG.height / 2;
	}
	function set_scrollYCenter(value) {
		return camGame.scroll.y = value - FlxG.height / 2;
	}

	public var customManagers:Map<String, Array<Dynamic>> = [];
	public var lastGettedManager:MobileControlManager;
	public var lastGettedManagerName:String;
	public static function checkManager(?managerName:String):MobileControlManager {
		if (managerName == null || managerName == '') {
			instance.lastGettedManagerName = 'default';
			instance.lastGettedManager = MusicBeatState.getState().mobileManager;
		}
		else if (instance.lastGettedManagerName != managerName) {
			instance.lastGettedManagerName = managerName;
			instance.lastGettedManager = instance.customManagers.get(managerName)[0];
		}
		return instance.lastGettedManager;
	}

	public function createNewManager(name:String, keyDetectionAllowed:Bool) {
		var mobileManagerNew = new MobileControlManager(this);
		var managerShit:Array<Dynamic> = [mobileManagerNew, keyDetectionAllowed];
		customManagers.set(name, managerShit);
		if(!variables.exists(name))
			variables.set(name, mobileManagerNew);
		if(!variables.exists(name + '_mobilePad'))
			variables.set(name + '_mobilePad', mobileManagerNew.mobilePad);
		if(!variables.exists(name + '_hitbox'))
			variables.set(name + '_hitbox', mobileManagerNew.hitbox);
		if(!variables.exists(name + '_joyStick'))
			variables.set(name + '_joyStick', mobileManagerNew.joyStick);
	}

	public static function checkMPadPress(buttonName:String, type = 'justPressed', ?managerName:String) {
		var manager = checkManager(managerName);

		var button:MobileButton = null;
		if (manager.mobilePad != null) button = manager.mobilePad.getButton(buttonName);
		if (button != null) return Reflect.getProperty(button, type);
		return false;
	}

	//for lua shit
	public static function checkHBoxPress(button:String, type = 'justPressed', ?managerName:String) {
		var manager = checkManager(managerName);

		var buttonObject:MobileButton = null;
		if (manager.hitbox != null) buttonObject = manager.hitbox.getButton(button);
		if (buttonObject != null) return Reflect.getProperty(buttonObject, type);
		return false;
	}

	//Lua Stuff for Mobile Controls
	public function reloadPlayStateHitbox(?mode:String)
	{
		removePlayStateHitbox();
		addPlayStateHitbox(mode);
	}

	public function addPlayStateHitbox(?mode:String, ?makeInvinsibleFirst:Bool, ?hints:Null<Bool>)
	{
		if (hints == null)
			hints = ClientPrefs.data.hitboxHint;

		mobileManager.addHitbox(mode, hints);
		mobileManager.addHitboxCamera();
		if (replayData == null && !cpuControlled) connectControlToNotes(null, 'hitbox');
		if (makeInvinsibleFirst) mobileManager.hitbox.visible = false;
		addHitboxDeadZone(null, ['buttonT', 'buttonC', 'buttonP']);
	}

	public function addHitboxDeadZone(?managerName:String, deadZoneButtons:Array<String>) {
		var manager = checkManager(managerName);
		manager?.hitbox.forEachAlive((button) ->
		{
			for (deadButton in deadZoneButtons) {
				if (manager.mobilePad?.getButton(deadButton) != null)
					button.deadZones.push(manager.mobilePad?.getButton(deadButton));
			}
		});
	}

	public function connectControlToNotes(?managerName:String, ?control:String) {
		var manager = checkManager(managerName);
		var currentControl:MobileButton;

		switch(control) {
			case 'mobilePad':
				manager.mobilePad?.onButtonDown?.add(onButtonPress);
				manager.mobilePad?.onButtonUp?.add(onButtonRelease);
				manager.mobilePad?.onButtonDown?.add((button:MobileButton, ids:Array<String>, unique:Int) -> replayRecorder?.recordKeyMobileC(Conductor?.songPosition, ids, 0));
				manager.mobilePad?.onButtonUp?.add((button:MobileButton, ids:Array<String>, unique:Int) -> replayRecorder?.recordKeyMobileC(Conductor?.songPosition, ids, 1));
			case 'hitbox':
				manager.hitbox?.onButtonDown?.add(onButtonPress);
				manager.hitbox?.onButtonUp?.add(onButtonRelease);
				mobileManager.hitbox?.onButtonDown?.add((button:MobileButton, ids:Array<String>, unique:Int) -> replayRecorder?.recordKeyMobileC(Conductor?.songPosition, ids, 0));
				mobileManager.hitbox?.onButtonUp?.add((button:MobileButton, ids:Array<String>, unique:Int) -> replayRecorder?.recordKeyMobileC(Conductor?.songPosition, ids, 1));
		}
	}

	public function removePlayStateHitbox()
	{
		mobileManager?.hitbox?.forEachAlive((button) ->
		{
			button.deadZones = [];
		});
		mobileManager?.removeHitbox();
	}
}

@:publicFields
class PlayStatePlayer {
	public var player:Player;
	public var ratingPercent: Float = 0.;
	public var ratingName: String = '?';
	public var ratingFC: String = null;
	public var combo: Int = 0;

	function calcHits() {
		return player.sicks + player.goods + player.bads + player.shits;
	}

	// all the encountered notes
	function calcTotalPlayed() {
		return player.sicks + player.goods + player.bads + player.shits + player.misses;
	}

	function calcTotalNotesHit() {
		return 
			(player.sicks * PlayState.instance.ratingsData[0].ratingMod) + 
			(player.goods * PlayState.instance.ratingsData[1].ratingMod) + 
			(player.bads * PlayState.instance.ratingsData[2].ratingMod) +
			(player.shits * PlayState.instance.ratingsData[3].ratingMod)
		;
	}

	function recalculateRating() {
		var totalPlayed = calcTotalPlayed();
		var totalNotesHit = calcTotalNotesHit();
		var ratingStuff = PlayState.ratingStuff;

		if (totalPlayed != 0) // Prevent divide by 0 
		{
			// Rating Percent
			ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));

			// Rating Name
			ratingName = Language.getText(ratingStuff[ratingStuff.length - 1][0]); // Uses last string
			if (ratingPercent < 1)
				for (i in 0...ratingStuff.length - 1)
					if (ratingPercent < ratingStuff[i][1]) {
						ratingName = Language.getText(ratingStuff[i][0]);
						break;
					}
		}

		ratingFC = 'Clear';
		if (player.misses < 1) {
			if (player.shits > 0) ratingFC = 'NM';
			if (player.bads > 0) ratingFC = 'FC';
			else if (player.goods > 0) ratingFC = 'GFC';
			else if (player.sicks > 0) ratingFC = 'SFC';
		}
		else if (player.misses < 10)
			ratingFC = 'SDCB';
	}

	function new(player:Player) {
		this.player = player;
	}
}