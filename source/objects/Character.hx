package objects;

import openfl.display.Sprite;

import backend.animation.PsychAnimationController;

import flixel.util.FlxSort;
import flixel.util.FlxDestroyUtil;

import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.FlxG;

import openfl.utils.AssetType;
import openfl.utils.Assets;
import openfl.display.MovieClip;
import openfl.geom.Rectangle;
import openfl.geom.Matrix;
import openfl.display.BitmapData;

import haxe.Json;

import backend.Song;
import states.stages.objects.TankmenBG;

#if sys
import sys.io.File;
import sys.FileSystem;
import haxe.zip.Reader;
import haxe.io.BytesInput;
#end

#if flxanimate
import flxanimate.FlxAnimate;
#end

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
	var vocals_file:String;
	@:optional var _editor_isPlayer:Null<Bool>;

	// SWF extras (optional)
	@:optional var swf_library:String;
	@:optional var swf_symbol:String;
}

typedef AnimArray = {
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

class Character extends FlxSprite
{
	public static final DEFAULT_CHARACTER:String = 'bf';

	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;
	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

       public var paused:Bool = false;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var animationNotes:Array<Dynamic> = [];
	public var stunned:Bool = false;
	public var singDuration:Float = 4;
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false;
	public var skipDance:Bool = false;

	public var healthIcon:String = 'face';
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var missingCharacter:Bool = false;
	public var missingText:FlxText;
	public var hasMissAnimations:Bool = false;
	public var vocalsFile:String = '';

	public var imageFile:String = '';
	public var jsonScale:Float = 1;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var editorIsPlayer:Null<Bool> = null;

	#if flxanimate
	public var isAnimateAtlas:Bool = false;
	public var atlas:FlxAnimate;
	#end

	// --- SWF branch (real OpenFL playback -> rasterized into the Flixel sprite) ---
	public var isSwf(default, null):Bool = false;
	var swfMC:MovieClip = null;
	var swfBounds:Rectangle;
	var swfMatrix:Matrix;
	var swfBuffer:BitmapData;
	var swfCurrentLabel:String = "";

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false)
	{
		super(x, y);

		animation = new PsychAnimationController(this);

		animOffsets = new Map<String, Array<Dynamic>>();
		this.isPlayer = isPlayer;
		changeCharacter(character);

		switch(curCharacter)
		{
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
			case 'pico-blazin', 'darnell-blazin':
				skipDance = true;
		}
	}

	public function changeCharacter(character:String)
	{
		animationsArray = [];
		animOffsets = [];
		curCharacter = character;
		var characterPath:String = 'characters/$character.json';

		var path:String = Paths.getPath(characterPath, TEXT);
		#if MODS_ALLOWED
		if (!FileSystem.exists(path))
		#else
		if (!Assets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER + '.json');
			missingCharacter = true;
			missingText = new FlxText(0, 0, 300, 'ERROR:\n$character.json', 16);
			missingText.alignment = CENTER;
		}

		try
		{
			#if MODS_ALLOWED
			loadCharacterFile(Json.parse(File.getContent(path)));
			#else
			loadCharacterFile(Json.parse(Assets.getText(path)));
			#end
		}
		catch(e:Dynamic)
		{
			trace('Error loading character file of "$character": $e');
		}

		skipDance = false;
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
		recalculateDanceIdle();
		dance();
	}

	public function loadCharacterFile(json:Dynamic)
	{
		// reset SWF bits
		isSwf = false;
		swfMC = null;
		swfBuffer = null;

		#if flxanimate
		isAnimateAtlas = false;

		// check normal AnimateAtlas
		var animToFind:String = Paths.getPath('images/' + json.image + '/Animation.json', TEXT);
		if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
			isAnimateAtlas = true;

		// check .zip SWF exports (data.json, library.json, symbols/)
		#if sys
		if (!isAnimateAtlas)
		{
			var swfZip:String = Paths.getPath('images/' + json.image + '.zip', BINARY);
			if (FileSystem.exists(swfZip)) isAnimateAtlas = true;
		}
		#end
		#end

		// --- SWF (true MovieClip) detection BEFORE atlases if the JSON explicitly asks for it ---
		// Prefer explicit swf_library, otherwise try treating `image` as a library id
		var swfLibrary:String = Reflect.hasField(json, "swf_library") ? Std.string(json.swf_library) : null;
		var swfSymbol:String  = Reflect.hasField(json, "swf_symbol")  ? Std.string(json.swf_symbol)  : null;

		if (swfLibrary == null && Assets.hasLibrary(json.image))
			swfLibrary = json.image;

		if (swfLibrary != null && Assets.hasLibrary(swfLibrary))
		{
			try {
				// If symbol is omitted, OpenFL returns the main timeline
				swfMC = (swfSymbol != null && swfSymbol.length > 0)
					? Assets.getMovieClip(swfLibrary + ":" + swfSymbol)
					: Assets.getMovieClip(swfLibrary);

				if (swfMC != null)
				{
					isSwf = true;

					// Measure bounds once, allocate buffer, and plug it into this FlxSprite
					swfBounds = swfMC.getBounds(swfMC);
					if (swfBounds == null) swfBounds = new Rectangle(0, 0, 1, 1);

					var bw = Math.max(1, Std.int(Math.ceil(swfBounds.width)));
					var bh = Math.max(1, Std.int(Math.ceil(swfBounds.height)));
					swfBuffer = new BitmapData(Std.int(Std.int(Std.int(Std.int(Std.int(Std.int(Std.int(bw))))))), Std.int(Std.int(Std.int(Std.int(Std.int(Std.int(Std.int(bh))))))), true, 0x00000000);
					loadGraphic(swfBuffer, false);

					// Prepare draw matrix (translate so content's top-left is 0,0)
					swfMatrix = new Matrix();
					swfMatrix.translate(-swfBounds.x, -swfBounds.y);

					// Start playing
					swfMC.gotoAndPlay(1);
					swfCurrentLabel = (swfMC.currentLabel != null) ? swfMC.currentLabel : "";

					// Clear atlas flag if any was detected; SWF takes precedence when requested
					#if flxanimate
					isAnimateAtlas = false;
					atlas = null;
					#end
				}
			} catch (e:Dynamic) {
				trace('SWF load failed (library="$swfLibrary", symbol="$swfSymbol"): $e');
			}
		}

		// --- If NOT SWF, proceed with your existing atlas/PNG paths ---
		if (!isSwf)
		{
			scale.set(1, 1);
			updateHitbox();

			if(!#if flxanimate isAnimateAtlas #else false #end)
			{
				frames = Paths.getMultiAtlas(json.image.split(','));
			}
			#if flxanimate
			else
			{
				atlas = new FlxAnimate();
				atlas.showPivot = false;

				try
				{
					// handle zip or normal
					#if sys
					var swfZip:String = Paths.getPath('images/' + json.image + '.zip', BINARY);
					if (FileSystem.exists(swfZip))
					{
						var bytes = File.getBytes(swfZip);
						var reader = new Reader(new BytesInput(bytes));
						var entries = reader.read();

						var dataJson:String = null;
						var libJson:String = null;

						for (entry in entries)
						{
							if (StringTools.endsWith(entry.fileName, "data.json"))
								dataJson = entry.data.toString();
							else if (StringTools.endsWith(entry.fileName, "library.json"))
								libJson = entry.data.toString();
						}

						if (dataJson != null && libJson != null)
						{
							// Psych’s FlxAnimate expects 2-arg loadAtlas(data, library) in 1.0.4
							atlas.loadAtlas(dataJson);
						}
						else
						{
							trace('SWF zip found but missing data.json or library.json');
						}
					}
					else
					#end
					{
						// Normal AnimateAtlas folder (Animation.json / spritemap*.json + png)
						if (isPaused) atlas.anim.pause(); else atlas.anim.resume();
					}
				}
				catch(e:haxe.Exception)
				{
					FlxG.log.warn('Could not load atlas ${json.image}: $e');
					trace(e.stack);
				}
			}
			#end
		}

		imageFile = json.image;
		jsonScale = json.scale;

		if(json.scale != 1) {
			scale.set(jsonScale, jsonScale);
			updateHitbox();
		}

		positionArray = json.position;
		cameraPosition = json.camera_position;

		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		flipX = (json.flip_x != isPlayer);
		healthColorArray = (json.healthbar_colors != null && json.healthbar_colors.length > 2) ? json.healthbar_colors : [161, 161, 161];
		vocalsFile = json.vocals_file != null ? json.vocals_file : '';
		originalFlipX = (json.flip_x == true);
		editorIsPlayer = json._editor_isPlayer;

		noAntialiasing = (json.no_antialiasing == true);
		antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

		// Only add Flixel/Animate animations if NOT a raw SWF MovieClip
		if (!isSwf)
		{
			animationsArray = json.animations;
			if(animationsArray != null && animationsArray.length > 0) {
				for (anim in animationsArray) {
					var animAnim:String = '' + anim.anim;
					var animName:String = '' + anim.name;
					var animFps:Int = anim.fps;
					var animLoop:Bool = !!anim.loop;
					var animIndices:Array<Int> = anim.indices;

					#if flxanimate
					if(isAnimateAtlas)
					{
						if(animIndices != null && animIndices.length > 0)
							atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, animFps, animLoop);
						else
							atlas.anim.addBySymbol(animAnim, animName, animFps, animLoop);
					}
					else
					#end
					{
						if(animIndices != null && animIndices.length > 0)
							animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop);
						else
							animation.addByPrefix(animAnim, animName, animFps, animLoop);
					}

					if(anim.offsets != null && anim.offsets.length > 1) addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
					else addOffset(anim.anim, 0, 0);
				}
			}
			#if flxanimate
			if(isAnimateAtlas) copyAtlasValues();
			#end
		}
	}

	override function update(elapsed:Float)
	{
		#if flxanimate
		if(isAnimateAtlas) atlas.update(elapsed);
		#end

		// SWF: we just keep the MovieClip playing; redraw happens in draw()
		if (isSwf && swfMC != null)
		{
			// keep note of label name for getAnimationName()
			var lbl = swfMC.currentLabel;
			if (lbl != null) swfCurrentLabel = lbl;
		}

		if(debugMode || (
			#if flxanimate
			(!isAnimateAtlas && !isSwf && animation.curAnim == null) || (isAnimateAtlas && (atlas.anim.curInstance == null || atlas.anim.curSymbol == null))
			#else
			(!isSwf && animation.curAnim == null)
			#end
		))
		{
			super.update(elapsed);
			return;
		}

		if(heyTimer > 0)
		{
			var rate:Float = (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
			heyTimer -= elapsed * rate;
			if(heyTimer <= 0)
			{
				var anim:String = getAnimationName();
				if(specialAnim && (anim == 'hey' || anim == 'cheer'))
				{
					specialAnim = false;
					dance();
				}
				heyTimer = 0;
			}
		}
		else if(specialAnim && isAnimationFinished())
		{
			specialAnim = false;
			dance();
		}
		else if (getAnimationName().endsWith('miss') && isAnimationFinished())
		{
			dance();
			finishAnimation();
		}

		switch(curCharacter)
		{
			case 'pico-speaker':
				if(animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0])
				{
					var noteData:Int = 1;
					if(animationNotes[0][1] > 2) noteData = 3;

					noteData += FlxG.random.int(0, 1);
					playAnim('shoot' + noteData, true);
					animationNotes.shift();
				}
				#if flxanimate
				if(isAnimateAtlas && atlas.anim.curInstance != null && atlas.anim.curSymbol != null && atlas.anim.finished)
					playAnim(getAnimationName(), false, false, atlas.anim.length - 3);
				#end
		}

		if (getAnimationName().startsWith('sing')) holdTimer += elapsed;
		else if(isPlayer) holdTimer = 0;

		if (!isPlayer && holdTimer >= Conductor.stepCrochet * (0.0011 #if FLX_PITCH / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1) #end) * singDuration)
		{
			dance();
			holdTimer = 0;
		}

		var name:String = getAnimationName();
		#if flxanimate
		if(isAnimateAtlas && atlas.anim.finished && hasAnimation('$name-loop'))
			playAnim('$name-loop');
		else
		#end
		if(!isSwf && animation.curAnim != null && animation.curAnim.finished && hasAnimation('$name-loop'))
			playAnim('$name-loop');

		super.update(elapsed);
	}

	// ---- Psych helpers (kept working for all branches) ----

	public function isAnimationNull():Bool
	{
		if (isSwf) return (swfMC == null);
		#if flxanimate
		return !isAnimateAtlas ? (animation.curAnim == null) : (atlas.anim.curInstance == null || atlas.anim.curSymbol == null);
		#else
		return (animation.curAnim == null);
		#end
	}

	var _lastPlayedAnimation:String = "";
	public function getAnimationName():String
	{
		if (isSwf) return (swfCurrentLabel != null) ? swfCurrentLabel : "";
		return _lastPlayedAnimation;
	}

	public function isAnimationFinished():Bool
	{
		if (isSwf) return false; // MovieClip timelines loop unless stopped
		#if flxanimate
		if (isAnimateAtlas) return atlas.anim.finished;
		#end
		return (animation.curAnim != null) ? animation.curAnim.finished : false;
	}

	public function finishAnimation():Void
	{
		if(isAnimationNull()) return;

		if (isSwf) swfMC.stop();
		#if flxanimate
		else if(isAnimateAtlas) atlas.anim.curFrame = atlas.anim.length - 1;
		#end
		else animation.curAnim.finish();
	}

	public function hasAnimation(anim:String):Bool
	{
		if (isSwf) return true; // allow any label name; playAnim will try
		return animOffsets.exists(anim);
	}

	public var animPaused(get, set):Bool;
	private function get_animPaused():Bool
	{
		if(isAnimationNull()) return false;
		if (isSwf) return !swfMC.currentFrame >= 0;
		#if flxanimate
		return !isAnimateAtlas ? animation.curAnim.paused : !atlas.anim.isPlaying;
		#else
		return animation.curAnim.paused;
		#end
	}
	private function set_animPaused(value:Bool):Bool
	{
		if(isAnimationNull()) return value;
		if (isSwf)
		{
			if (isPaused) swfMC.stop(); else swfMC.play();
			return value;
		}
		#if flxanimate
		if(!isAnimateAtlas) animation.curAnim.paused = value;
		else {
			if(value) atlas.anim.pause(); else atlas.anim.resume();
		}
		#else
		animation.curAnim.paused = value;
		#end
		return value;
	}

	public var danced:Bool = false;

	public function dance()
	{
		if (!debugMode && !skipDance && !specialAnim)
		{
			if(danceIdle)
			{
				danced = !danced;

				if (danced) playAnim('danceRight' + idleSuffix);
				else        playAnim('danceLeft' + idleSuffix);
			}
			else if(hasAnimation('idle' + idleSuffix))
				playAnim('idle' + idleSuffix);
		}
	}

	public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void
	{
		specialAnim = false;

		if (isSwf && swfMC != null)
		{
			// Try to use a frame label that matches the animation name
			try {
				// If label does not exist, gotoAndPlay will just ignore; we keep last played
				swfMC.gotoAndPlay(AnimName);
				swfCurrentLabel = AnimName;
			} catch (_:Dynamic) {}
		}
		else
		{
			#if flxanimate
			if(isAnimateAtlas) {
				atlas.anim.play(AnimName, Force, Reversed, Frame);
				atlas.update(0);
			} else
			#end
			{
				animation.play(AnimName, Force, Reversed, Frame);
			}
		}

		_lastPlayedAnimation = AnimName;

		if (hasAnimation(AnimName) && animOffsets.exists(AnimName))
		{
			var daOffset = animOffsets.get(AnimName);
			offset.set(daOffset[0], daOffset[1]);
		}

		if (curCharacter.startsWith('gf-') || curCharacter == 'gf')
		{
			if (AnimName == 'singLEFT')  danced = true;
			else if (AnimName == 'singRIGHT') danced = false;
			if (AnimName == 'singUP' || AnimName == 'singDOWN') danced = !danced;
		}
	}

	function loadMappedAnims():Void
	{
		try
		{
			var songData:SwagSong = Song.getChart('picospeaker', Paths.formatToSongPath(Song.loadedSongName));
			if(songData != null)
				for (section in songData.notes)
					for (songNotes in section.sectionNotes)
						animationNotes.push(songNotes);

			TankmenBG.animationNotes = animationNotes;
			animationNotes.sort(sortAnims);
		}
		catch(e:Dynamic) {}
	}

	function sortAnims(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	public var danceEveryNumBeats:Int = 2;
	private var settingCharacterUp:Bool = true;
	public function recalculateDanceIdle() {
		var lastDanceIdle:Bool = danceIdle;
		danceIdle = (hasAnimation('danceLeft' + idleSuffix) && hasAnimation('danceRight' + idleSuffix));

		if(settingCharacterUp)
		{
			danceEveryNumBeats = (danceIdle ? 1 : 2);
		}
		else if(lastDanceIdle != danceIdle)
		{
			var calc:Float = danceEveryNumBeats;
			if(danceIdle) calc /= 2; else calc *= 2;
			danceEveryNumBeats = Math.round(Math.max(calc, 1));
		}
		settingCharacterUp = false;
	}

	public function addOffset(name:String, x:Float = 0, y:Float = 0)
	{
		animOffsets[name] = [x, y];
	}

	public function quickAnimAdd(name:String, anim:String)
	{
		animation.addByPrefix(name, anim, 24, false);
	}

	// ---------- Rendering ----------
	#if flxanimate
	public override function draw()
	{
		// SWF: render the MovieClip to our buffer, then let Flixel draw the pixels
		if (isSwf && swfMC != null && swfBuffer != null)
		{
			swfBuffer.fillRect(swfBuffer.rect, 0x00000000);
			swfBuffer.draw(swfMC, swfMatrix, null, null, null, true);
			dirty = true; // tell Flixel to re-upload texture if needed
			super.draw();
			return;
		}

		if(isAnimateAtlas)
		{
			if(atlas.anim.curInstance != null)
			{
				copyAtlasValues();
				atlas.draw();
				return;
			}
		}
		super.draw();
	}

	public function copyAtlasValues()
	{
		@:privateAccess
		{
			atlas.cameras = cameras;
			atlas.scrollFactor = scrollFactor;
			atlas.scale = scale;
			atlas.offset = offset;
			atlas.origin = origin;
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
		}
	}

	public override function destroy()
	{
		atlas = FlxDestroyUtil.destroy(atlas);
		if (swfBuffer != null) { swfBuffer.dispose(); swfBuffer = null; }
		swfMC = null;
		super.destroy();
	}
	#else
	public override function draw()
	{
		// SWF render path even if flxanimate isn't compiled
		if (isSwf && swfMC != null && swfBuffer != null)
		{
			swfBuffer.fillRect(swfBuffer.rect, 0x00000000);
			swfBuffer.draw(swfMC, swfMatrix, null, null, null, true);
			dirty = true;
		}
		super.draw();
	}
	#end
}
