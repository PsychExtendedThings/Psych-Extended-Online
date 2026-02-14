#if !macro
//Discord API
#if DISCORD_ALLOWED
import backend.Discord;
#end
import haxe.xml.Access;

//Import all funkin stuff (cne stuff)
import funkin.backend.*;
import funkin.backend.system.*;
import funkin.backend.shaders.*;
import funkin.backend.scripting.*;
import funkin.backend.scripting.events.*;
import funkin.backend.scripting.events.sprite.*;
import funkin.backend.utils.*;
import funkin.backend.assets.*;
import funkin.backend.FunkinSprite;
import funkin.backend.utils.XMLUtil;
import funkin.backend.scripting.events.sprite.PlayAnimContext;
import funkin.backend.system.interfaces.IBeatReceiver;
import funkin.backend.system.interfaces.IOffsetCompatible;
import funkin.backend.utils.XMLUtil.AnimData;
import funkin.backend.utils.XMLUtil.BeatAnim;
import funkin.backend.utils.XMLUtil.IXMLEvents;

#if sys
import sys.*;
import sys.io.*;
#elseif js
import js.html.*;
#end

//Psych
#if LUA_ALLOWED
import llua.*;
import llua.Lua;
#end

#if ACHIEVEMENTS_ALLOWED
import backend.Achievements;
#end

#if flxanimate
import flxanimate.FlxAnimate;
#end

#if lumod
import lumod.Lumod;
#end

/* Some Stuff */
import vlc.MP4Handler;

#if HSC_ALLOWED
import funkin.backend.scripting.HScript.Script;
import funkin.backend.scripting.HScript.ScriptPack;
import funkin.backend.scripting.events.CancellableEvent;
import funkin.backend.FunkinSprite;
import funkin.backend.FunkinText;
import haxe.io.Path;
#end

import backend.Paths;
import backend.Controls;
import backend.CoolUtil;
import backend.MusicBeatState;
import backend.MusicBeatSubstate;
import backend.CustomFadeTransition;
import backend.ClientPrefs;
import backend.Conductor;
import backend.BaseStage;
import backend.Difficulty;
import backend.Mods;

import objects.Alphabet;
import objects.BGSprite;

import states.PlayState;
import states.LoadingState;

//Flixel
#if (flixel >= "5.3.0")
import flixel.sound.FlxSound;
#else
import flixel.system.FlxSound;
#end
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.math.FlxPoint;
import flixel.system.FlxAssets.FlxShader;
import haxe.ds.StringMap;
import online.backend.Deflection;

// Mobile Controls

// Spesificly Extended Mobile-Controls Library Objects For FNF
#if TOUCH_CONTROLS
import mobile.objects.FunkinMobilePad;
import mobile.objects.FunkinHitbox;
import mobile.objects.FunkinJoyStick;
#end
// Others
import backend.FunkinFileSystem;
#if TOUCH_CONTROLS
import mobile.ScreenUtil;
import mobile.MobileConfig;
import mobile.MobileButton;
import mobile.backend.StorageUtil;
import mobile.substates.MobileExtraControl;
#end
import mobile.MobileControlManager;
//Android
#if android
import android.callback.CallBack as AndroidCallBack;
import android.content.Context as AndroidContext;
import android.widget.Toast as AndroidToast;
import android.os.Environment as AndroidEnvironment;
import android.Permissions as AndroidPermissions;
import android.Settings as AndroidSettings;
import android.Tools as AndroidTools;
import android.os.Build.VERSION as AndroidVersion;
import android.os.Build.VERSION_CODES as AndroidVersionCode;
#end

import online.backend.Deflection;

using StringTools;
using ArrayTools;

#if away3d
import away3d.tools.utils.Drag3D;
#end
#end