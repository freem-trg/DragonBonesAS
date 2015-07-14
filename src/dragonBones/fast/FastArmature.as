package dragonBones.fast
{
	import flash.events.EventDispatcher;
	
	import dragonBones.animation.IAnimatable;
	import dragonBones.cache.AnimationCacheManager;
	import dragonBones.core.dragonBones_internal;
	import dragonBones.events.AnimationEvent;
	import dragonBones.events.FrameEvent;
	import dragonBones.fast.animation.FastAnimation;
	import dragonBones.fast.animation.FastAnimationState;
	import dragonBones.objects.ArmatureData;
	import dragonBones.objects.DragonBonesData;
	import dragonBones.objects.Frame;

	use namespace dragonBones_internal;
	
	/**
	 * Dispatched when an animation state play complete (if playtimes equals to 0 means loop forever. Then this Event will not be triggered)
	 */
	[Event(name="complete", type="dragonBones.events.AnimationEvent")]
	
	/**
	 * Dispatched when an animation state complete a loop.
	 */
	[Event(name="loopComplete", type="dragonBones.events.AnimationEvent")]
	
	/**
	 * Dispatched when an animation state enter a frame with animation frame event.
	 */
	[Event(name="animationFrameEvent", type="dragonBones.events.FrameEvent")]
	
	/**
	 * Dispatched when an bone enter a frame with animation frame event.
	 */
	[Event(name="boneFrameEvent", type="dragonBones.events.FrameEvent")]
	
	public class FastArmature extends EventDispatcher implements IAnimatable
	{
		/**
		 * The name should be same with ArmatureData's name
		 */
		public var name:String;
		/**
		 * An object that can contain any user extra data.
		 */
		public var userData:Object;
		
		
		public var enableCache:Boolean;
		
		/**
		 * 保证CacheManager是独占的前提下可以开启，开启后有助于性能提高
		 */
		public var isCacheManagerExclusive:Boolean = false;
		
		/** @private */
		protected var _animation:FastAnimation;
		
		/** @private */
		protected var _display:Object;
		
		/** @private Store bones based on bones' hierarchy (From root to leaf)*/
		public var boneList:Vector.<FastBone>;
		dragonBones_internal var _boneDic:Object;
		
		/** @private Store slots based on slots' zOrder*/
		public var slotList:Vector.<FastSlot>;
		dragonBones_internal var _slotDic:Object;
		
		public var slotHasChildArmatureList:Vector.<FastSlot>;
		
		dragonBones_internal var __dragonBonesData:DragonBonesData;
		dragonBones_internal var _armatureData:ArmatureData;
		dragonBones_internal var _slotsZOrderChanged:Boolean;
		dragonBones_internal var _eventList:Array;
		
		private var _delayDispose:Boolean;
		private var _lockDispose:Boolean;
		private var useCache:Boolean = true;
		public function FastArmature(display:Object)
		{
			super(this);
			_display = display;
			_animation = new FastAnimation(this);
			_slotsZOrderChanged = false;
			_armatureData = null;
			
			boneList = new Vector.<FastBone>;
			_boneDic = {};
			slotList = new Vector.<FastSlot>;
			_slotDic = {};
			slotHasChildArmatureList = new Vector.<FastSlot>;
			
			_eventList = [];
			
			_delayDispose = false;
			_lockDispose = false;
			
		}
		
		/**
		 * Cleans up any resources used by this instance.
		 */
		public function dispose():void
		{
			_delayDispose = true;
			if(!_animation || _lockDispose)
			{
				return;
			}
			
			userData = null;
			
			_animation.dispose();
			var i:int = slotList.length;
			while(i --)
			{
				slotList[i].dispose();
			}
			i = boneList.length;
			while(i --)
			{
				boneList[i].dispose();
			}
			
			slotList.fixed = false;
			slotList.length = 0;
			boneList.fixed = false;
			boneList.length = 0;
			
			_armatureData = null;
			_animation = null;
			slotList = null;
			boneList = null;
			_eventList = null;
			
		}
		
		/**
		 * Update the animation using this method typically in an ENTERFRAME Event or with a Timer.
		 * @param The amount of second to move the playhead ahead.
		 */
		
		public function advanceTime(passedTime:Number):void
		{
			_lockDispose = true;
			_animation.advanceTime(passedTime);
			
			var bone:FastBone;
			var slot:FastSlot;
			var i:int;
			if(_animation.animationState.isUseCache())
			{
				if(!useCache)
				{
					useCache = true;
				}
				i = slotList.length;
				while(i --)
				{
					slot = slotList[i];
					slot.updateByCache();
				}
			}
			else
			{
				if(useCache)
				{
					useCache = false;
					i = slotList.length;
					while(i --)
					{
						slot = slotList[i];
						slot.switchTransformToBackup();
					}
				}
				
				i = boneList.length;
				while(i --)
				{
					bone = boneList[i];
					bone.update();
				}
				
				i = slotList.length;
				while(i --)
				{
					slot = slotList[i];
					slot.update();
				}
			}
			
			i = slotHasChildArmatureList.length;
			while(i--)
			{
				slot = slotList[i];
				var childArmature:FastArmature = slot.childArmature;
				if(childArmature)
				{
					childArmature.advanceTime(passedTime);
				}
			}
			
			if(_slotsZOrderChanged)
			{
				updateSlotsZOrder();
			}
			
			while(_eventList.length > 0)
			{
				this.dispatchEvent(_eventList.shift());
			}
			
			_lockDispose = false;
			if(_delayDispose)
			{
				dispose();
			}
		}

		public function enableAnimationCache(frameRate:int, animationList:Array = null):AnimationCacheManager
		{
			var animationCacheManager:AnimationCacheManager = AnimationCacheManager.initWithArmatureData(armatureData,frameRate);
			if(animationList)
			{
				for each(var animationName:String in animationList)
				{
					animationCacheManager.initAnimationCache(animationName);
				}
			}
			else
			{
				animationCacheManager.initAllAnimationCache();
			}
			animationCacheManager.setCacheGeneratorArmature(this);
			animationCacheManager.generateAllAnimationCache();
			
			animationCacheManager.bindCacheUserArmature(this);
			enableCache = true;
			return animationCacheManager;
		}
		
		dragonBones_internal function _updateBonesByCache():void
		{
			var i:int = boneList.length;
			var bone:FastBone;
			while(i --)
			{
				bone = boneList[i];
				bone.update();
			}
		}
		
		
		/**
		 * Add a Bone instance to this Armature instance.
		 * @param A Bone instance.
		 * @param (optional) The parent's name of this Bone instance.
		 * @see dragonBones.Bone
		 */
		dragonBones_internal function addBone(bone:FastBone, parentName:String = null):void
		{
			var parentBone:FastBone;
			if(parentName)
			{
				parentBone = getBone(parentName);
			}
			bone.armature = this;
			bone.setParent(parentBone);
			boneList.unshift(bone);
			_boneDic[bone.name] = bone;
		}
		
		/**
		 * Add a slot to a bone as child.
		 * @param slot A Slot instance
		 * @param boneName bone name
		 * @see dragonBones.core.DBObject
		 */
		dragonBones_internal function addSlot(slot:FastSlot, parentBoneName:String):void
		{
			var bone:FastBone = getBone(parentBoneName);
			if(bone)
			{
				slot.armature = this;
				slot.setParent(bone);
				slot.addDisplayToContainer(display);
				slotList.push(slot);
				_slotDic[slot.name] = slot;
				if(slot.hasChildArmature)
				{
					slotHasChildArmatureList.push(slot);
				}
				
			}
			else
			{
				throw new ArgumentError();
			}
		}
		
		/**
		 * Sort all slots based on zOrder
		 */
		dragonBones_internal function updateSlotsZOrder():void
		{
			slotList.fixed = false;
			slotList.sort(sortSlot);
			slotList.fixed = true;
			var i:int = slotList.length;
			while(i --)
			{
				var slot:FastSlot = slotList[i];
				slot.addDisplayToContainer(_display);
			}
			
			_slotsZOrderChanged = false;
		}
		
		private function sortBoneList():void
		{
			var i:int = boneList.length;
			if(i == 0)
			{
				return;
			}
			var helpArray:Array = [];
			while(i --)
			{
				var level:int = 0;
				var bone:FastBone = boneList[i];
				var boneParent:FastBone = bone;
				while(boneParent)
				{
					level ++;
					boneParent = boneParent.parent;
				}
				helpArray[i] = [level, bone];
			}
			
			helpArray.sortOn("0", Array.NUMERIC|Array.DESCENDING);
			
			i = helpArray.length;
			
			boneList.fixed = false;
			while(i --)
			{
				boneList[i] = helpArray[i][1];
			}
			boneList.fixed = true;
			
			helpArray.length = 0;
		}
		
		/** @private When AnimationState enter a key frame, call this func*/
		dragonBones_internal function arriveAtFrame(frame:Frame, animationState:FastAnimationState):void
		{
			if(frame.event && this.hasEventListener(FrameEvent.ANIMATION_FRAME_EVENT))
			{
				var frameEvent:FrameEvent = new FrameEvent(FrameEvent.ANIMATION_FRAME_EVENT);
				frameEvent.animationState = animationState;
				frameEvent.frameLabel = frame.event;
				_eventList.push(frameEvent);
			}

			if(frame.action)
			{
				animation.gotoAndPlay(frame.action);
			}
		}
		
		dragonBones_internal function resetAnimation():void
		{
			animation.animationState.resetTimelineStateList();
			for each(var boneItem:FastBone in boneList)
			{
				boneItem._timelineState = null;
			}
		}
		
		private function sortSlot(slot1:FastSlot, slot2:FastSlot):int
		{
			return slot1.zOrder < slot2.zOrder?1: -1;
		}
		
		/**
		 * ArmatureData.
		 * @see dragonBones.objects.ArmatureData.
		 */
		public function get armatureData():ArmatureData
		{
			return _armatureData;
		}
		
		/**
		 * An Animation instance
		 * @see dragonBones.animation.Animation
		 */
		public function get animation():FastAnimation
		{
			return _animation;
		}
		
		/**
		 * Armature's display object. It's instance type depends on render engine. For example "flash.display.DisplayObject" or "startling.display.DisplayObject"
		 */
		public function get display():Object
		{
			return _display;
		}
		
		
		public function getBone(boneName:String):FastBone
		{
			return _boneDic[boneName];
		}
		public function getSlot(slotName:String):FastSlot
		{
			return _slotDic[slotName];
		}
	}
}