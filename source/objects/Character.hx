package objects;

import flx3d.FlxSprite3D;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxTileFrames;
import flixel.math.FlxRect;
import flixel.math.FlxPoint;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.util.FlxSort;
import flixel.util.FlxDestroyUtil;
#if MODS_ALLOWED
import sys.io.File;
import sys.FileSystem;
#end
import openfl.utils.AssetType;
import openfl.utils.Assets;
import tjson.TJSON as Json;
import backend.Song;
import backend.Section;
import states.stages.objects.TankmenBG;
import online.GameClient;
import flixel.addons.effects.FlxSkewedSprite;

import backend.Converters;

typedef CharacterFile = {
    var animations:Array<AnimArray>;
    var image:String;
    var scale:Float;
    var sing_duration:Float;
    var healthicon:String;

    var position:Array<Float>;
    var camera_position:Array<Float>;

    var flip_x:Bool;
    var no_antialiasing:Bool;
    var healthbar_colors:Array<Int>;
    @:optional var betterOffsets:Bool;
    @:optional var codenameOffsets:Bool;
    @:optional var isPlayer:Bool;
    @:optional var vocals_file:String;
    @:optional var dead_character:Null<String>;
    @:optional var results_character:Null<String>;
    @:optional var speaker:Null<String>;
}

typedef AnimArray = {
    var anim:String;
    var name:String;
    var fps:Int;
    var loop:Bool;
    var indices:Array<Int>;
    var offsets:Array<Int>;
    @:optional var sound:String;
    @:optional var flip_x:Bool;
}

class CharacterCameraPoint extends FlxBasePoint {
    public var charType:String = null;

    public function new(character:Character, charType:String) {
        super(0, 0);
        this.charType = charType;
    }

    override function get_x():Float {
        if (PlayState.instance != null) {
            switch (charType) {
                case 'bf':
                    if (!PlayState.instance.boyfriend.codenameOffsets)
                        return PlayState.instance.boyfriendCameraOffset[0];
                case 'gf':
                    if (!PlayState.instance.gf.codenameOffsets)
                        return PlayState.instance.girlfriendCameraOffset[0];
                case 'dad':
                    if (!PlayState.instance.dad.codenameOffsets)
                        return PlayState.instance.opponentCameraOffset[0];
            }
        }
        return super.get_x();
    }

    override function set_x(Value:Float):Float {
        if (PlayState.instance != null) {
            switch (charType) {
                case 'bf':
                    if (PlayState.instance.boyfriend != null && !PlayState.instance.boyfriend.codenameOffsets)
                        PlayState.instance.boyfriendCameraOffset[0] = Value;
                case 'gf':
                    if (PlayState.instance.gf != null && !PlayState.instance.gf.codenameOffsets)
                        PlayState.instance.girlfriendCameraOffset[0] = Value;
                case 'dad':
                    if (PlayState.instance.dad != null && !PlayState.instance.dad.codenameOffsets)
                        PlayState.instance.opponentCameraOffset[0] = Value;
            }
        }
        return super.set_x(Value);
    }

    override function get_y():Float {
        if (PlayState.instance != null) {
            switch (charType) {
                case 'bf':
                    if (!PlayState.instance.boyfriend.codenameOffsets)
                        return PlayState.instance.boyfriendCameraOffset[1];
                case 'gf':
                    if (!PlayState.instance.gf?.codenameOffsets)
                        return PlayState.instance.girlfriendCameraOffset[1];
                case 'dad':
                    if (!PlayState.instance.dad.codenameOffsets)
                        return PlayState.instance.opponentCameraOffset[1];
            }
        }
        return super.get_y();
    }

    override function set_y(Value:Float):Float {
        if (PlayState.instance != null) {
            switch (charType) {
                case 'bf':
                    if (PlayState.instance.boyfriend != null && !PlayState.instance.boyfriend.codenameOffsets)
                        PlayState.instance.boyfriendCameraOffset[1] = Value;
                case 'gf':
                    if (PlayState.instance.gf != null && !PlayState.instance.gf.codenameOffsets)
                        PlayState.instance.girlfriendCameraOffset[1] = Value;
                case 'dad':
                    if (PlayState.instance.dad != null && !PlayState.instance.dad.codenameOffsets)
                        PlayState.instance.opponentCameraOffset[1] = Value;
            }
        }
        return super.set_y(Value);
    }
}

class Character extends FlxSkewedSprite {
    public var globalOffset:FlxPoint = FlxPoint.get(0, 0);
    public var extraOffset:FlxPoint = FlxPoint.get(0, 0);
    public var lastHit:Float = Math.NEGATIVE_INFINITY;
    public var ghostDraw:Bool = false;

    @:noCompletion var __swappedLeftRightAnims:Bool = false;
    @:noCompletion var __reverseTrailProcedure:Bool = false;

    public inline function getCameraPosition() {
		var midpoint:FlxPoint = getMidpoint();
		var event = EventManager.get(PointEvent).recycle(
			midpoint.x + (isPlayer ? -100 : 150) + globalOffset.x + cameraOffset.x,
			midpoint.y - 100 + globalOffset.y + cameraOffset.y);

		midpoint.put();
		return new FlxPoint(event.x, event.y);
	}

    public dynamic function beforeTrailCache() {
        if (codenameOffsets && isFlippedOffsets()) {
            flipX = !flipX;
            scale.x *= -1;
            __reverseTrailProcedure = true;
        }
    }
    
    public dynamic function afterTrailCache() {
        if (codenameOffsets && __reverseTrailProcedure) {
            flipX = !flipX;
            scale.x *= -1;
            __reverseTrailProcedure = false;
        }
    }

    public function swapLeftRightAnimations() {
        if (codenameOffsets) {
            var variants = ['']; 
            var pose = 'singRIGHT';
            var animList:Array<String> = [];
            
            if (!isAnimateAtlas && animation != null) {
                animList = animation.getNameList();
            }
            
            for (a in animList) {
                if (a != pose && StringTools.startsWith(a, pose)) {
                    variants.push(a.substring(pose.length));
                }
            }

            for (i in variants) {
                if (!isAnimateAtlas) {
                    var leftAnim = animation.getByName('singLEFT$i');
                    var rightAnim = animation.getByName('singRIGHT$i');
                    if (leftAnim != null && rightAnim != null) {
                        CoolUtil.switchAnimFrames(rightAnim, leftAnim);
                    }
                }
                switchOffset('singLEFT$i', 'singRIGHT$i');
            }
            __swappedLeftRightAnims = true;
        } else {
            if (animation.getByName('singRIGHT') != null && animation.getByName('singLEFT') != null)
                CoolUtil.switchAnimFrames(animation.getByName('singRIGHT'), animation.getByName('singLEFT'));
            if (animation.getByName('singRIGHTmiss') != null && animation.getByName('singLEFTmiss') != null)
                CoolUtil.switchAnimFrames(animation.getByName('singRIGHTmiss'), animation.getByName('singLEFTmiss'));

            switchOffset('singLEFT', 'singRIGHT');
            switchOffset('singLEFTmiss', 'singRIGHTmiss');
        }
    }

    public function switchOffset(anim1:String, anim2:String)
    {
        if (animOffsets.exists(anim1) && animOffsets.exists(anim2)) {
            var old1 = animOffsets.get(anim1);
            var old2 = animOffsets.get(anim2);
            animOffsets.set(anim1, old2);
            animOffsets.set(anim2, old1);
        }
    }
    
    public inline function getAnimOffset(name:String)
    {
        if (animOffsets.exists(name))
            return animOffsets.get(name);
        return [0, 0];
    }

    public var cameraOffset:FlxPoint;

    public var animOffsets:Map<String, Array<Dynamic>>;
    public var debugMode:Bool = false;

    public var isPlayer:Bool = false;
    public var curCharacter:String = DEFAULT_CHARACTER;
    public var isMissing:Bool = false;
    public var resultsName:String = null;
    public var speakerName:String = null;

    public var speaker:FlxSprite = null;

    public var colorTween:FlxTween;
    public var noteHold(default, set):Bool = false;
    function set_noteHold(v) {
        if (PlayState.isCharacterPlayer(this) && noteHold != v) {
            GameClient.send("noteHold", v);
        }
        return noteHold = v;
    }
    public var holdTimer:Float = 0;
    public var heyTimer:Float = 0;
    public var specialAnim:Bool = false;
    public var animationNotes:Array<Dynamic> = [];
    public var stunned:Bool = false;
    public var singDuration:Float = 4;
    public var idleSuffix:String = '';
    public var danceIdle:Bool = false;
    public var skipDance:Bool = false;
    public var vocalsFile:String = '';
    public var deadName:String = null;

    public var gameIconIndex:Int = 0;
    public var healthIcon:String = 'face';
    public var animationsArray:Array<AnimArray> = [];

    public var positionArray:Array<Float> = [0, 0];
    var ogPositionArray:Array<Float> = [0, 0];
    public var cameraPosition:Array<Float> = [0, 0];

    public var ox:Int = 0;

    public var hasMissAnimations:Bool = true;
    public var imageFile:String = '';
    public var jsonScale:Float = 1;
    public var noAntialiasing:Bool = false;
    public var originalFlipX:Bool = false;
    public var healthColorArray:Array<Int> = [255, 0, 0];

    public var isSkin:Bool = false;
    public var loadFailed:Bool = false;

    public var animSounds:Map<String, openfl.media.Sound> = new Map<String, openfl.media.Sound>();
    public var sound:FlxSound;

    public var modDir:String = null;

    public var animSuffix:String;

    public var onAtlasAnimationComplete:String->Void;

    public var Custom(get, set):Bool;
    
    function set_Custom(value:Bool):Bool
    {
        return this.isSkin = value;
    }

    function get_Custom():Bool
    {
        return this.isSkin;
    }

    public var custom(get,never):Bool;

    function get_custom():Bool
    {
        return this.isSkin;
    }

    function set_custom(value:Bool):Bool
    {
        return this.isSkin = value;
    }
    public static var DEFAULT_CHARACTER:String = 'bf';

    public static function getCharacterFile(character:String, ?instance:Character, ?nullOnFail:Bool = false):CharacterFile {
        var jsonCharacterPath:String = 'characters/' + character + '.json';
        var xmlCharacterPath:String = 'data/characters/' + character + '.xml';

        var finalPath:String = null;
        var isXml:Bool = false;

        #if MODS_ALLOWED
        var xmlPath:String = Paths.modFolders(xmlCharacterPath);
        if (!FunkinFileSystem.exists(xmlPath)) {
            xmlPath = Paths.getPreloadPath(xmlCharacterPath);
        }

        if (FunkinFileSystem.exists(xmlPath)) {
            finalPath = xmlPath;
            isXml = true;
        } else {
            var jsonPath:String = Paths.modFolders(jsonCharacterPath);
            if (!FunkinFileSystem.exists(jsonPath)) {
                jsonPath = Paths.getPreloadPath(jsonCharacterPath);
            }

            if (FunkinFileSystem.exists(jsonPath)) {
                finalPath = jsonPath;
                isXml = false;
            }
        }
        #else
        var xmlPath:String = Paths.getPreloadPath(xmlCharacterPath);
        if (Assets.exists(xmlPath)) {
            finalPath = xmlPath;
            isXml = true;
        } else {
            var jsonPath:String = Paths.getPreloadPath(jsonCharacterPath);
            if (Assets.exists(jsonPath)) {
                finalPath = jsonPath;
                isXml = false;
            }
        }
        #end

        if (finalPath == null) {
            if (instance != null)
                instance.loadFailed = true;
            if (nullOnFail)
                return null;
                
            finalPath = Paths.getPreloadPath('characters/' + DEFAULT_CHARACTER + '.json');
            isXml = false;
        }

        var rawText = FunkinFileSystem.getText(finalPath);
        if (rawText == null) return null;

        if (isXml) {
            var convertedJsonStr = Converters.parseCodenameChar(rawText, character);
            return cast Json.parse(convertedJsonStr);
        } else {
            return cast Json.parse(rawText);
        }
    }

    public function loadSpeaker() {
        if (speakerName != null && speakerName.trim().length > 0) {
            if (speakerName == 'abot') {
                final json = Character.getCharacterFile(speakerName + (PlayState.isPixelStage ? '-pixel' : ''));
                var abot = new states.stages.objects.ABotSpeaker(json.position[0], json.position[1], PlayState.curStage == 'spooky-erect', PlayState.isPixelStage);
                abot.updateABotEye(0, true);
                speaker = abot;
            }
            
            if (speaker == null) {
                speaker = new Character(0, 0, speakerName, false, false, 'gf');
            }
        }

        return speaker;
    }

    var charType:String = null;

    public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false, ?isSkin:Bool = false, ?charType:String) {
        super(x, y);

        this.charType = charType;

        modDir = Mods.currentModDirectory;

        switch (character) {
            case 'pico-playable':
                character = 'pico-player';
        }

        animOffsets = new Map<String, Array<Dynamic>>();
        cameraOffset = new CharacterCameraPoint(this, charType);
        this.isPlayer = isPlayer;
        this.isSkin = isSkin;
        var library:String = null;
        changeCharacter(character);

        if (curCharacter.endsWith('-speaker') && loadMappedAnims()) {
            playAnim("shoot1");
        }
    }
    
    public function loadCharacterFile(json:Dynamic, ?charType:String)
    {
        isAnimateAtlas = false;

        var split:Array<String> = json.image.split(',');
        imageFile = split[0].trim();

        #if MODS_ALLOWED
        var modAnimToFind:String = Paths.modFolders('images/' + imageFile + '/Animation.json');
        var animToFind:String = Paths.getPath('images/' + imageFile + '/Animation.json', TEXT);
        if (FunkinFileSystem.exists(modAnimToFind) || FunkinFileSystem.exists(animToFind) || Assets.exists(animToFind))
        #else
        if (Assets.exists(Paths.getPath('images/' + imageFile + '/Animation.json', TEXT)))
        #end
        isAnimateAtlas = true;

        if (!isAnimateAtlas) {
            frames = Paths.getAtlas(imageFile);
        }
        #if flxanimate
        else
        {
            atlas = new FlxAnimate();
            atlas.showPivot = false;
            try
            {
                Paths.loadAnimateAtlas(atlas, imageFile);
            }
            catch(e:Dynamic)
            {
                FlxG.log.warn('Could not load atlas ${imageFile}: $e');
                trace('Could not load atlas ${imageFile}: $e');
            }

            @:privateAccess
            {
                frames = new FlxTileFrames(FlxGraphic.fromRectangle(0, 0, FlxColor.TRANSPARENT, false, '0x0_transparent'));
                frames.addEmptyFrame(new FlxRect(0, 0));
            }
        }
        #end

        if (!isAnimateAtlas && frames != null) {
            for (_imgFile in split) {
                final imgFile = _imgFile.trim(); 
                if (!imageFile.contains(imgFile))
                    imageFile += ',$imgFile';
                var daAtlas = Paths.getAtlas(imgFile);
                if (daAtlas != null)
                    cast(frames, FlxAtlasFrames).addAtlas(daAtlas);
            }
        }

        if (json.scale != 1) {
            jsonScale = json.scale;
            scale.set(jsonScale, jsonScale);
            updateHitbox();
        }

        if (json.position != null) {
            ogPositionArray = positionArray = json.position;
            globalOffset.set(positionArray[0], positionArray[1]);
        }
        cameraPosition = json.camera_position;
        cameraOffset.set(cameraPosition[0], cameraPosition[1]);

        healthIcon = json.healthicon;
        singDuration = json.sing_duration;
        flipX = (json.flip_x == true);
        betterOffsets = (json.betterOffsets == true);
        codenameOffsets = (json.codenameOffsets == true);
        playerOffsets = (json.isPlayer == true);

        if (json.healthbar_colors != null && json.healthbar_colors.length > 2)
            healthColorArray = json.healthbar_colors;

        vocalsFile = json.vocals_file ?? curCharacter;
        
        deadName = json.dead_character;
        resultsName = json.results_character;
        speakerName = json.speaker;

        noAntialiasing = (json.no_antialiasing == true);
        antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

        animationsArray = json.animations;
        if (animationsArray != null && animationsArray.length > 0) {
            for (anim in animationsArray) {
                var animAnim:String = '' + anim.anim;
                var animName:String = '' + anim.name;
                var animFps:Int = anim.fps;
                var animLoop:Bool = !!anim.loop;
                var animIndices:Array<Int> = anim.indices;
                var flipX:Bool = !!anim.flip_x;
                if(!isAnimateAtlas)
                {
                    if (animIndices != null && animIndices.length > 0) {
                        animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop, flipX);
                    }
                    else {
                        animation.addByPrefix(animAnim, animName, animFps, animLoop, flipX);
                    }
                }
                #if flxanimate
                else
                {
                    try {
                        if(animIndices != null && animIndices.length > 0)
                            atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, animFps, animLoop);
                        else if (atlas.anim.symbolDictionary.exists(animName))
                            atlas.anim.addBySymbol(animAnim, animName, animFps, animLoop);
                        else
                            atlas.anim.addByFrameLabel(animAnim, animName, animFps, animLoop);
                    }
                    catch (exc) {
                        trace('couldnt add flxanimate animation');
                        trace(exc);
                    }
                }
                #end

                if (anim.offsets != null && anim.offsets.length > 1) 
                    addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
                else
                    addOffset(anim.anim, 0, 0);

                if (anim.sound != null) {
                    var sound = Paths.sound(anim.sound);
                    if (sound != null)
                        animSounds.set(animAnim, sound);
                }
            }
        }
        else {
            quickAnimAdd('idle', 'BF idle dance');
        }

        #if flxanimate
        if(isAnimateAtlas) copyAtlasValues();
        #end
    }
    
    public function changeCharacter(character:String, ?charType:String) {
        animationsArray = [];
        animOffsets = [];
        curCharacter = character;

        switch (curCharacter) {
            default:
                var json:CharacterFile = getCharacterFile(curCharacter, this);
                try
                {
                    loadCharacterFile(json, charType);
                }
                catch(e:Dynamic)
                {
                    trace('Error loading character file of "$character": $e');
                }
        }
        originalFlipX = flipX;

        if(animOffsets.exists('singLEFTmiss') || animOffsets.exists('singDOWNmiss') || animOffsets.exists('singUPmiss') || animOffsets.exists('singRIGHTmiss')) hasMissAnimations = true;
        recalculateDanceIdle();
        if (isPlayer != playerOffsets && (betterOffsets || codenameOffsets))
            swapLeftRightAnimations();

        dance();

        if (isPlayer) {
            flipX = !flipX;
        }
        __baseFlipped = flipX;
    }

    public var sprite3D:FlxSprite3D;

    function init3D() {
        if (loadFailed || !(FlxG.state is PlayState) || PlayState.instance.stage3D == null)
            return;

        final stageObjects = PlayState.instance?.stageData?.stage3D?.objects;
        if (stageObjects == null || stageObjects.get(charType)?.position == null)
            return;

        visible = false;
        sprite3D = PlayState.instance.stage3D.add(this);
        sprite3D.followVisibility = false;
        final originGroup = switch (charType) {
            case 'gf': PlayState.instance.gfGroup;
            case 'dad': PlayState.instance.dadGroup;
            case 'bf': PlayState.instance.boyfriendGroup;
            default: null;
        }
        if (originGroup != null)
            sprite3D.z -= originGroup.members.indexOf(this) * 0.0001;
        PlayState.instance.stage3D.setPositionFromArray(sprite3D, stageObjects.get(charType).position);
    }

    public var noAnimationBullshit:Bool = false;
    public var noHoldBullshit:Bool = false;

    public var isFirstUpdate:Bool = true;

    override function update(elapsed:Float) {
        if (isFirstUpdate) {
            isFirstUpdate =  false;

            init3D();
        }

        if(isAnimateAtlas) {
            atlas.update(elapsed);
        }

        if (noAnimationBullshit) {
            super.update(elapsed);
            return;
        }

        if (!debugMode && !isAnimationNull()) {
            if (heyTimer > 0) {
                heyTimer -= elapsed * (PlayState.instance?.playbackRate ?? 1);
                if (heyTimer <= 0) {
                    var anim:String = getAnimationName();

                    if (specialAnim && anim == 'hey' || anim == 'cheer') {
                        specialAnim = false;
                        dance();
                    }
                    heyTimer = 0;
                }
            }
            else if (specialAnim && isAnimationFinished()) {
                specialAnim = false;
                dance();
            }
            else if ((getAnimationName().endsWith('miss') || isMissing) && isAnimationFinished()) {
                dance();
                finishAnimation();
            }

            if (animationNotes != null && animationNotes.length > 0) {
                if (Conductor.songPosition > animationNotes[0][0]) {
                    var noteData:Int = 1;
                    if (animationNotes[0][1] > 2)
                        noteData = 3;

                    noteData += FlxG.random.int(0, 1);
                    playAnim('shoot' + noteData, true);
                    animationNotes.shift();
                }
            }

            if (getAnimationName().startsWith('sing'))
                holdTimer += elapsed;
            else if (PlayState.isCharacterPlayer(this) || GameClient.isConnected())
                holdTimer = 0;

            if (!noHoldBullshit && holdTimer >= Conductor.stepCrochet * (0.0011 / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1)) * singDuration) {
                dance();
                holdTimer = 0;
            }

            var name:String = getAnimationName();
            if(isAnimationFinished() && animOffsets.exists('$name-loop'))
                playAnim('$name-loop');
        }
        super.update(elapsed);
    }

    inline public function isAnimationNull():Bool
        return !isAnimateAtlas ? (animation.curAnim == null) : (atlas.anim.curSymbol == null);

    public function getAnimName():String {
        return getAnimationName();
    }

    inline public function getAnimationName():String
    {
        var name:String = '';
        @:privateAccess
        if(!isAnimationNull()) name = !isAnimateAtlas ? animation.curAnim.name : atlas.anim.curSymbol.name;
        return (name != null) ? name : '';
    }

    public function isAnimationFinished():Bool
    {
        if(isAnimationNull()) return false;
        return !isAnimateAtlas ? animation.curAnim.finished : atlas.anim.finished;
    }

    public function finishAnimation():Void
    {
        if(isAnimationNull()) return;
        if(!isAnimateAtlas) animation.curAnim.finish();
        else atlas.anim.curFrame = atlas.anim.length - 1;
    }

    public var animPaused(get, set):Bool;
    private function get_animPaused():Bool
    {
        if(isAnimationNull()) return false;
        return !isAnimateAtlas ? animation.curAnim.paused : atlas.anim.isPlaying;
    }
    private function set_animPaused(value:Bool):Bool
    {
        if(isAnimationNull()) return value;
        if(!isAnimateAtlas) animation.curAnim.paused = value;
        else
        {
            if(value) atlas.anim.pause();
            else atlas.anim.resume();
        } 
        return value;
    }

    public var danced:Bool = false;

    public function dance() {
        if (!debugMode && !skipDance && !specialAnim) {
            if (danceIdle) {
                danced = !danced;

                if (danced)
                    playAnim('danceRight' + idleSuffix);
                else
                    playAnim('danceLeft' + idleSuffix);
            }
            else if (animOffsets.exists('idle' + idleSuffix)) {
                playAnim('idle' + idleSuffix);
            }
        }
    }

    final randomDirections:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT'];

    var colorTransformBefore:Array<Float> = [1, 1, 1];
    var colorTransformWasChanged:Bool = false;

    public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void {
        if (AnimName == null)
            return;

        if (animSuffix != null)
            AnimName += animSuffix;

        if (AnimName.contains("sing") || AnimName.contains("miss"))
            lastHit = Conductor.songPosition;

        if(colorTransform != null && colorTransformWasChanged) {
            colorTransform.redMultiplier = colorTransformBefore[0];
            colorTransform.greenMultiplier = colorTransformBefore[1];
            colorTransform.blueMultiplier = colorTransformBefore[2];
        }

        specialAnim = false;
        isMissing = AnimName.endsWith("miss");

        if (AnimName == "taunt" || AnimName == "taunt-alt") {
            specialAnim = true;
            heyTimer = 1;
        }

        if (!animExists(AnimName)) {
            if (AnimName == "ready" && !animExists(AnimName)) {
                AnimName = "taunt";
            }

            if ((AnimName == "taunt" || AnimName == "taunt-alt") && !animExists(AnimName)) {
                if (AnimName == "taunt-alt")
                    AnimName = "hey-alt";
                else
                    AnimName = "hey";
            }

            if (AnimName.endsWith("-alt") && !animExists(AnimName)) {
                AnimName = AnimName.substring(0, AnimName.length - "-alt".length);
            }
            
            if (AnimName == "hurt" && !animExists(AnimName)) {
                AnimName = 'sing' + randomDirections[FlxG.random.int(0, randomDirections.length - 1)] + 'miss';
            }

            if (AnimName == "hey" && !animExists(AnimName)) {
                if (curCharacter.startsWith("tankman")) {
                    AnimName = "singUP-alt";
                }
                else {
                    AnimName = "singUP";
                }
            }

            if (AnimName.startsWith("sing") && !animExists(AnimName)) {
                for (anim in ['singLEFT', 'singRIGHT', 'singODD', 'singUP', 'singDOWN']) {
                    if (AnimName.startsWith(anim)) {
                        AnimName = anim + (AnimName.contains('miss') ? 'miss' : '');
                        break;
                    }
                }
            }

            if (AnimName.startsWith("singODD") && !animExists(AnimName)) {
                AnimName = 'singUP' + (AnimName.contains('miss') ? 'miss' : '');
            }

            if (AnimName.endsWith("miss") && !animExists(AnimName)) {
                AnimName = AnimName.substring(0, AnimName.length - "miss".length);

                colorTransformBefore = [colorTransform.redMultiplier, colorTransform.greenMultiplier, colorTransform.blueMultiplier];
                colorTransformWasChanged = true;

                colorTransform.redMultiplier = 0.5;
                colorTransform.greenMultiplier = 0.3;
                colorTransform.blueMultiplier = 0.5;
            }
        }

        if (animSounds != null && animSounds.exists(AnimName)) {
            if (sound != null) {
                sound.stop();
                sound.destroy();
                sound = null;
            }

            sound = FlxG.sound.play(animSounds.get(AnimName));
            if (sound != null) {
                sound.onComplete = () -> {
                    sound.destroy();
                    sound = null;
                };
            }
        }

        if(!isAnimateAtlas) animation.play(AnimName, Force, Reversed, Frame);
        else {
            atlas.anim.play(AnimName, Force, Reversed, Frame);
            atlasPlayingAnim = AnimName;
            
            // Fix: Prevent memory leaks from constantly adding to the signal list
            atlas.anim.onComplete.removeAll();
            atlas.anim.onComplete.add(() -> {
                if (onAtlasAnimationComplete != null)
                    onAtlasAnimationComplete(AnimName);
                if (animation != null && animation.curAnim != null) animation.finish();
            });

            final symbol = atlas.anim?.curSymbol;
            final element = atlas.anim?.curInstance;
            if (symbol != null && element != null && element.symbol != null && !animation.exists(AnimName)) {
                animation.add(AnimName, [for (_ in 0...symbol.length) 0], atlas.anim.framerate, element.symbol.loop == Loop);
            }
            if (animation.exists(AnimName))
                animation.play(AnimName, Force, Reversed, Frame);
        }

        if (codenameOffsets) {
            var daOffset = getAnimOffset(AnimName);
            frameOffset.set(daOffset[0], daOffset[1]);
            offset.set((isPlayer != playerOffsets) ? globalOffset.x : -globalOffset.x, -globalOffset.y);
        } else if (betterOffsets) {
            var daOffset = getAnimOffset(AnimName);
            frameOffset.set(daOffset[0], daOffset[1]);
            offset.set((isPlayer != playerOffsets) ? -globalOffset.x : globalOffset.x, -globalOffset.y);
        } else {
            var daOffset = getAnimOffset(AnimName);
            if (daOffset != null)
                offset.set(daOffset[0], daOffset[1]);
            else
                offset.set(0, 0);
                
            frameOffset.set(0, 0); // Fix: Prevent carry over from other offset modes
        }

        if (curCharacter.startsWith('gf')) {
            if (AnimName == 'singLEFT') {
                danced = true;
            }
            else if (AnimName == 'singRIGHT') {
                danced = false;
            }

            if (AnimName == 'singUP' || AnimName == 'singDOWN') {
                danced = !danced;
            }
        }

        if (AnimName == 'redheadsAnim') {
            animSuffix = '-bloody';
        }
    }

    public function setPositionToFeet(v:Bool) {
        if (!v) {
            positionArray[0] = ogPositionArray[0];
            positionArray[1] = ogPositionArray[1];
            return;
        }

        positionArray[0] = -(width / 2) + ogPositionArray[0];
        positionArray[1] = -(height) + ogPositionArray[1];
    }

    public function animExists(AnimName:String) {
        return animOffsets.exists(AnimName);
    }

    function loadMappedAnims():Bool {
        var noteData:Array<SwagSection> = null;
        try {
            noteData = Song.loadFromJson('picospeaker', Paths.formatToSongPath(PlayState.SONG.song)).notes;
        }
        catch (exc) {
            trace("Failed to load picospeaker.json!");
            trace(exc);
        }
        if (noteData == null)
            return false;
        for (section in noteData) {
            for (songNotes in section.sectionNotes) {
                animationNotes.push(songNotes);
            }
        }
        TankmenBG.animationNotes = animationNotes;
        animationNotes.sort(sortAnims);
        return true;
    }

    function sortAnims(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int {
        return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
    }

    public var danceEveryNumBeats:Int = 2;

    private var settingCharacterUp:Bool = true;

    public function recalculateDanceIdle() {
        var lastDanceIdle:Bool = danceIdle;
        danceIdle = (animOffsets.exists('danceLeft' + idleSuffix) && animOffsets.exists('danceRight' + idleSuffix));

        if (settingCharacterUp) {
            danceEveryNumBeats = (danceIdle ? 1 : 2);
        }
        else if (lastDanceIdle != danceIdle) {
            var calc:Float = danceEveryNumBeats;
            if (danceIdle)
                calc /= 2;
            else
                calc *= 2;

            danceEveryNumBeats = Math.round(Math.max(calc, 1));
        }
        settingCharacterUp = false;
    }

    public function addOffset(name:String, x:Float = 0, y:Float = 0) {
        animOffsets[name] = [x, y];
    }

    public function quickAnimAdd(name:String, anim:String)
    {
        if(!isAnimateAtlas)
            animation.addByPrefix(name, anim, 24, false);
        #if flxanimate
        else if (atlas.anim.symbolDictionary.exists(anim))
            atlas.anim.addBySymbol(name, anim, 24, false);
        else
            atlas.anim.addByFrameLabel(name, anim, 24, false);
        #end
    }

    public var isAnimateAtlas:Bool = false;
    #if flxanimate
    public var atlas:FlxAnimate;
    @:noCompletion public var atlasPlayingAnim:String;

    public function copyAtlasValues()
    {
        @:privateAccess
        {
            atlas.cameras = cameras;
            atlas.scrollFactor.set(scrollFactor.x, scrollFactor.y);
            atlas.scale.set(scale.x, scale.y);
            
            if (codenameOffsets) {
                // CNE's exact offset and frameOffset implementation
                atlas.offset.set(offset.x, offset.y);
                atlas.frameOffset.set(frameOffset.x, frameOffset.y);
            } else {
                // Combine offset and frameOffset so Better offsets apply to FlxAnimate
                atlas.offset.set(offset.x + frameOffset.x, offset.y + frameOffset.y); 
                atlas.frameOffset.set(0, 0);
            }
            
            atlas.x = x;
            atlas.y = y;
            atlas.angle = angle;
            atlas.alpha = alpha;
            atlas.visible = visible;
            atlas.flipX = flipX;
            atlas.flipY = flipY;
            atlas.shader = shader;
            atlas.antialiasing = antialiasing;
            atlas.colorTransform = colorTransform;
            atlas.color = color;

            atlas.skew.set(skew.x, skew.y);

            // Fix: DO NOT overwrite atlas.origin with Character's dummy 1x1 graphic origin!
            // Sync Character properties FROM the atlas so hitboxes and midpoints match correctly.
            origin.set(atlas.origin.x, atlas.origin.y);
            width = atlas.width;
            height = atlas.height;
        }
    }
    
    @:noCompletion var __baseFlipped:Bool = false;
    @:noCompletion var __reverseDrawProcedure:Bool = false;
    public override function getScreenBounds(?newRect:FlxRect, ?camera:FlxCamera):FlxRect {
        if (__reverseDrawProcedure) {
            scale.x *= -1;
            var bounds:FlxRect = super.getScreenBounds(newRect, camera);
            scale.x *= -1;
            return bounds;
        }
        return super.getScreenBounds(newRect, camera);
    }

    public var betterOffsets:Bool = false;
    public var codenameOffsets:Bool = false;
    public var playerOffsets:Bool = false;

    public function isFlippedOffsets()
        return (codenameOffsets && debugMode) ? false : (isPlayer != playerOffsets) != (flipX != __baseFlipped);

    var __reversePreDrawProcedure:Bool = false;

    public function preDraw() {
        if (!ghostDraw) {
            x += extraOffset.x;
            y += extraOffset.y;
        }

        if (__reversePreDrawProcedure = isFlippedOffsets()) {
            __reverseDrawProcedure = true;
            flipX = !flipX;
            scale.x *= -1;
        }
    }

    public function postDraw() {
        if (__reversePreDrawProcedure) {
            flipX = !flipX;
            scale.x *= -1;
            __reverseDrawProcedure = false;
        }

        if (!ghostDraw) {
            x -= extraOffset.x;
            y -= extraOffset.y;
        }
    }

    public override function draw()
    {
        // 1. Setup Phase
        if (codenameOffsets) {
            preDraw();
        } else if (betterOffsets && isFlippedOffsets()) {
            __reverseDrawProcedure = true;
            flipX = !flipX;
            scale.x *= -1;
        }

        // 2. Draw Phase
        if (isAnimateAtlas) {
            copyAtlasValues();
            atlas.draw();
        } else {
            super.draw();
        }

        // 3. Cleanup Phase
        if (codenameOffsets) {
            postDraw();
        } else if (betterOffsets && isFlippedOffsets()) {
            flipX = !flipX;
            scale.x *= -1;
            __reverseDrawProcedure = false;
        }
    }

    public function destroyAtlas()
    {
        if (atlas != null)
            atlas = FlxDestroyUtil.destroy(atlas);
    }
    #end

    override public function destroy() {
        super.destroy();

        if (sound != null) {
            sound.stop();
            sound.destroy();
            sound = null;
        }

        #if flxanimate
        destroyAtlas();
        #end

        if (PlayState.instance?.stage3D != null && sprite3D != null) {
            PlayState.instance.stage3D.remove(sprite3D);
            sprite3D.dispose();
            sprite3D = null;
        }
    }

    public function onCombo(from:Int, to:Int) {}
    public function onHealth(from:Float, to:Float) {}
}