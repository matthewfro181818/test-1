import backend.Discord;
import llua.*;
import llua.Lua;
import backend.Achievements;
import sys.*;
import sys.io.*;
import js.html.*;
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
import backend.Language;
import backend.ui.*; //Psych-UI
import objects.Alphabet;
import objects.BGSprite;
import states.PlayState;
import states.LoadingState;
import flxanimate.*;
import flxanimate.PsychFlxAnimate as FlxAnimate;
import flixel.sound.FlxSound;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.addons.transition.FlxTransitionableState;
import swf.exporters.swflite.SWFLite;
import swf.exporters.swflite.SWFLiteLibrary;
import swf.exporters.swflite.SpriteSymbol;

#if !macro
//Discord API
#if DISCORD_ALLOWED
#end

//Psych
#if LUA_ALLOWED
#end

#if ACHIEVEMENTS_ALLOWED
#end

#if sys
#elseif js
#end





#if flxanimate
#end

//Flixel

using StringTools;
#end
