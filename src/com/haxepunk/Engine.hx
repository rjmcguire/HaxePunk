package com.haxepunk;

import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.Sprite;
import flash.display.StageAlign;
import flash.display.StageDisplayState;
import flash.display.StageQuality;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.geom.Rectangle;
import flash.Lib;
import haxe.Timer;
import com.haxepunk.graphics.atlas.TextureAtlas;
import com.haxepunk.utils.Draw;
import com.haxepunk.utils.Input;
import com.haxepunk.Tweener;

/**
 * Main game Sprite class, added to the Flash Stage. Manages the game loop.
 */
class Engine extends Sprite
{
	/**
	 * If the game should stop updating/rendering.
	 */
	public var paused:Bool;

	/**
	 * Cap on the elapsed time (default at 30 FPS). Raise this to allow for lower framerates (eg. 1 / 10).
	 */
	public var maxElapsed:Float;

	/**
	 * The max amount of frames that can be skipped in fixed framerate mode.
	 */
	public var maxFrameSkip:Int;

	/**
	 * The amount of milliseconds between ticks in fixed framerate mode.
	 */
	public var tickRate:Int;

	/**
	 * Constructor. Defines startup information about your game.
	 * @param	width			The width of your game.
	 * @param	height			The height of your game.
	 * @param	frameRate		The game framerate, in frames per second.
	 * @param	fixed			If a fixed-framerate should be used.
	 */
	public function new(width:Int = 0, height:Int = 0, frameRate:Float = 60, fixed:Bool = false)
	{
		super();

		// global game properties
		HXP.bounds = new Rectangle(0, 0, width, height);
		HXP.assignedFrameRate = frameRate;
		HXP.fixed = fixed;

		// global game objects
		HXP.engine = this;
		HXP.screen = new Screen();
		HXP.width = width;
		HXP.height = height;

		// miscellaneous startup stuff
#if neko
		if (HXP.randomSeed == null) HXP.randomizeSeed();
#else
		if (HXP.randomSeed == 0) HXP.randomizeSeed();
#end

		HXP.entity = new Entity();
		HXP.time = Lib.getTimer();

		paused = false;
		maxElapsed = 0.0333;
		maxFrameSkip = 5;
		tickRate = 4;
		_frameList = new Array<Int>();
		_flashTime = _delta = _frameListSum = 0;
		_frameLast = 0;

		// on-stage event listener
#if flash
		if (Lib.current.stage != null) onStage();
		else Lib.current.addEventListener(Event.ADDED_TO_STAGE, onStage);
#else
		addEventListener(Event.ADDED_TO_STAGE, onStage);
		Lib.current.addChild(this);
#end
	}

	/**
	 * Override this, called after Engine has been added to the stage.
	 */
	public function init() { }

	/**
	 * Override this, called when game gains focus
	 */
	public function focusGained() { }

	/**
	 * Override this, called when game loses focus
	 */
	public function focusLost() { }

	/**
	 * Updates the game, updating the World and Entities.
	 */
	public function update()
	{
		if (HXP.tweener.active && HXP.tweener.hasTween) HXP.tweener.updateTweens();

		if (HXP.world.active)
		{
			if (HXP.world.hasTween) HXP.world.updateTweens();
			HXP.world.update();
		}
		HXP.world.updateLists();
		if (!HXP.gotoIsNull()) checkWorld();
	}

	/**
	 * Renders the game, rendering the World and Entities.
	 */
	public function render()
	{
		// timing stuff
		var t:Float = Lib.getTimer();
		if (_frameLast == 0) _frameLast = Std.int(t);

		// render loop
		HXP.screen.swap();
		Draw.resetTarget();
		HXP.screen.refresh();
		if (HXP.world.visible) HXP.world.render();
		HXP.screen.redraw();
		TextureAtlas.renderAll();

		// more timing stuff
		t = Lib.getTimer();
		_frameListSum += (_frameList[_frameList.length] = Std.int(t - _frameLast));
		if (_frameList.length > 10) _frameListSum -= _frameList.shift();
		HXP.frameRate = 1000 / (_frameListSum / _frameList.length);
		_frameLast = t;
	}

	/**
	 * Sets the game's stage properties. Override this to set them differently.
	 */
	public function setStageProperties()
	{
		HXP.stage.frameRate = HXP.assignedFrameRate;
		HXP.stage.align = StageAlign.TOP_LEFT;
		HXP.stage.quality = StageQuality.HIGH;
		HXP.stage.scaleMode = StageScaleMode.NO_SCALE;
		HXP.stage.displayState = StageDisplayState.NORMAL;

		resize(); // call resize once to initialize the screen

		// set resize event
		HXP.stage.addEventListener(Event.RESIZE, function (e:Event) {
			resize();
		});

		HXP.stage.addEventListener(Event.ACTIVATE, function (e:Event) {
			HXP.focused = true;
			focusGained();
			HXP.world.focusGained();
		});

		HXP.stage.addEventListener(Event.DEACTIVATE, function (e:Event) {
			HXP.focused = false;
			focusLost();
			HXP.world.focusLost();
		});
	}

	/** @private Event handler for stage resize */
	private function resize()
	{
		if (HXP.width == 0) HXP.width = HXP.stage.stageWidth;
		if (HXP.height == 0) HXP.height = HXP.stage.stageHeight;
		// calculate scale from width/height values
		HXP.screen.scaleX = HXP.stage.stageWidth / HXP.width;
		HXP.screen.scaleY = HXP.stage.stageHeight / HXP.height;
		HXP.resize(HXP.stage.stageWidth, HXP.stage.stageHeight);
	}

	/** @private Event handler for stage entry. */
	private function onStage(e:Event = null)
	{
		// remove event listener
#if flash
		if (e != null)
			Lib.current.removeEventListener(Event.ADDED_TO_STAGE, onStage);
		HXP.stage = Lib.current.stage;
		HXP.stage.addChild(this);
#else
		removeEventListener(Event.ADDED_TO_STAGE, onStage);
		HXP.stage = stage;
#end
		setStageProperties();

		// enable input
		Input.enable();

		// switch worlds
		if (!HXP.gotoIsNull()) checkWorld();

		// game start
		init();

		// start game loop
		_rate = 1000 / HXP.assignedFrameRate;
		if (HXP.fixed)
		{
			// fixed framerate
			_skip = _rate * (maxFrameSkip + 1);
			_last = _prev = Lib.getTimer();
			_timer = new Timer(tickRate);
			_timer.run = onTimer;
		}
		else
		{
			// nonfixed framerate
			_last = Lib.getTimer();
			addEventListener(Event.ENTER_FRAME, onEnterFrame);
		}
	}

	/** @private Framerate independent game loop. */
	private function onEnterFrame(e:Event)
	{
		// update timer
		_time = _gameTime = Lib.getTimer();
		HXP._flashTime = _time - _flashTime;
		_updateTime = _time;
		HXP.elapsed = (_time - _last) / 1000;
		if (HXP.elapsed > maxElapsed) HXP.elapsed = maxElapsed;
		HXP.elapsed *= HXP.rate;
		_last = _time;

		// update loop
		if (!paused) update();

		// update console
		if (HXP.consoleEnabled()) HXP.console.update();

		// update input
		Input.update();

		// update timer
		_time = _renderTime = Lib.getTimer();
		HXP._updateTime = _time - _updateTime;

		// render loop
		if (!paused) render();

		// update timer
		_time = _flashTime = Lib.getTimer();
		HXP._renderTime = _time - _renderTime;
		HXP._gameTime = _time - _gameTime;
	}

	/** @private Fixed framerate game loop. */
	private function onTimer()
	{
		// update timer
		_time = Lib.getTimer();
		_delta += (_time - _last);
		_last = _time;

		// quit if a frame hasn't passed
		if (_delta < _rate) return;

		// update timer
		_gameTime = Std.int(_time);
		HXP._flashTime = _time - _flashTime;

		// update loop
		if (_delta > _skip) _delta = _skip;
		while (_delta >= _rate)
		{
			HXP.elapsed = _rate * HXP.rate * 0.001;

			// update timer
			_updateTime = _time;
			_delta -= _rate;
			_prev = _time;

			// update loop
			if (!paused) update();

			// update console
			if (HXP.consoleEnabled()) HXP.console.update();

			// update input
			Input.update();

			// update timer
			_time = Lib.getTimer();
			HXP._updateTime = _time - _updateTime;
		}

		// update timer
		_renderTime = _time;

		// render loop
		if (!paused) render();

		// update timer
		_time = _flashTime = Lib.getTimer();
		HXP._renderTime = _time - _renderTime;
		HXP._gameTime =  _time - _gameTime;
	}

	/** @private Switch Worlds if they've changed. */
	private function checkWorld()
	{
		if (HXP.gotoIsNull()) return;

		if (HXP.world != null)
		{
			HXP.world.end();
			HXP.world.updateLists();
			if (HXP.world.autoClear && HXP.world.hasTween) HXP.world.clearTweens();
			HXP.swapWorld();
			HXP.camera = HXP.world.camera;
			HXP.world.updateLists();
			HXP.world.begin();
			HXP.world.updateLists();
		}
	}

	// Timing information.
	private var _delta:Float;
	private var _time:Float;
	private var _last:Float;
	private var _timer:Timer;
	private var	_rate:Float;
	private var	_skip:Float;
	private var _prev:Float;

	// Debug timing information.
	private var _updateTime:Float;
	private var _renderTime:Float;
	private var _gameTime:Float;
	private var _flashTime:Float;

	// FrameRate tracking.
	private var _frameLast:Float;
	private var _frameListSum:Int;
	private var _frameList:Array<Int>;
}