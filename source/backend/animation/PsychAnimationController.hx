package backend.animation;

import flixel.animation.FlxAnimationController;
import swf.exporters.swflite.SWFLite;
import swf.exporters.swflite.SWFLiteLibrary;
import swf.exporters.swflite.SpriteSymbol;



class PsychAnimationController extends FlxAnimationController {
    public var followGlobalSpeed:Bool = true;

    public override function update(elapsed:Float):Void {
		if (_curAnim != null) {
            var speed:Float = timeScale;
            if (followGlobalSpeed) speed *= FlxG.animationTimeScale;
			_curAnim.update(elapsed * speed);
		}
		else if (_prerotated != null) {
			_prerotated.angle = _sprite.angle;
		}
	}
}