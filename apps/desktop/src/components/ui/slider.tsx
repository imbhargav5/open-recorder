import {
	animate,
	progress as calcProgress,
	clamp,
	type HTMLMotionProps,
	type MotionStyle,
	mix,
	motion,
	type SpringOptions,
	useMotionValue,
	useReducedMotion,
	useTransform,
} from "motion/react";
import * as React from "react";
import { cn } from "@/lib/utils";

type SliderProps = Omit<HTMLMotionProps<"div">, "defaultValue" | "onChange" | "onValueChange"> & {
	value?: number[];
	defaultValue?: number[];
	min?: number;
	max?: number;
	step?: number;
	disabled?: boolean;
	orientation?: "horizontal";
	inverted?: boolean;
	onValueChange?: (value: number[]) => void;
	onValueCommit?: (value: number[]) => void;
	maxPull?: number;
	maxSquish?: number;
	maxStretch?: number;
	keyboardStep?: number;
	keyboardSpring?: SpringOptions;
};

const DEFAULT_KEYBOARD_SPRING: SpringOptions = { stiffness: 200, damping: 60 };
const DEFAULT_MAX_PULL = 18;
const DEFAULT_MAX_SQUISH = 0.92;
const DEFAULT_MAX_STRETCH = 1.08;
const SETTLE_SPRING: SpringOptions = { stiffness: 260, damping: 34 };

function getClientX(event: MouseEvent | PointerEvent | TouchEvent) {
	if ("touches" in event && event.touches[0]) {
		return event.touches[0].clientX;
	}

	if ("changedTouches" in event && event.changedTouches[0]) {
		return event.changedTouches[0].clientX;
	}

	return (event as MouseEvent | PointerEvent).clientX;
}

function getPrecision(step: number) {
	const stepString = `${step}`;
	if (!stepString.includes(".")) return 0;

	return stepString.split(".")[1]?.length ?? 0;
}

function valueToProgress(value: number, min: number, max: number) {
	if (max === min) return 0;

	return clamp(0, 1, (value - min) / (max - min));
}

function progressToValue(progress: number, min: number, max: number, step: number) {
	const raw = mix(min, max, clamp(0, 1, progress));
	const snapped = Math.round((raw - min) / step) * step + min;

	return Number(clamp(min, max, snapped).toFixed(getPrecision(step)));
}

const Slider = React.forwardRef<HTMLDivElement, SliderProps>(
	(
		{
			className,
			value,
			defaultValue,
			min = 0,
			max = 100,
			step = 1,
			disabled = false,
			orientation = "horizontal",
			inverted = false,
			onValueChange,
			onValueCommit,
			maxPull = DEFAULT_MAX_PULL,
			maxSquish = DEFAULT_MAX_SQUISH,
			maxStretch = DEFAULT_MAX_STRETCH,
			keyboardStep,
			keyboardSpring = DEFAULT_KEYBOARD_SPRING,
			"aria-label": ariaLabel,
			"aria-labelledby": ariaLabelledBy,
			onKeyDown: onKeyDownProp,
			onPointerCancel: onPointerCancelProp,
			onPointerDown: onPointerDownProp,
			onPointerMove: onPointerMoveProp,
			onPointerUp: onPointerUpProp,
			onTapStart: onTapStartProp,
			onPan: onPanProp,
			onPanEnd: onPanEndProp,
			style,
			...props
		},
		forwardedRef,
	) => {
		const ref = React.useRef<HTMLDivElement>(null);
		const initialDragX = React.useRef(0);
		const initialProgressX = React.useRef(0);
		const isInteracting = React.useRef(false);
		const isPointerInteracting = React.useRef(false);
		const didPointerSettle = React.useRef(false);
		const size = React.useRef({ left: 0, right: 0 });
		const shouldReduceMotion = useReducedMotion();

		const controlledValue = value?.[0];
		const [uncontrolledValue, setUncontrolledValue] = React.useState(
			defaultValue?.[0] ?? controlledValue ?? min,
		);
		const currentValue = clamp(min, max, controlledValue ?? uncontrolledValue);
		const progress = useMotionValue(valueToProgress(currentValue, min, max));
		const brightness = useTransform(() => clamp(0, 1, progress.get()));
		const x = useTransform(progress, [-1, 0, 1, 2], [-maxPull, 0, 0, maxPull]);
		const invertedX = useTransform(x, (latest) => -latest);
		const translateX = inverted ? invertedX : x;
		const { scaleX, scaleY } = useTransform(x, [-maxPull, 0, 0, maxPull], {
			scaleX: [maxStretch, 1, 1, maxStretch],
			scaleY: [maxSquish, 1, 1, maxSquish],
		});
		const fillOrigin = inverted ? 1 : 0;

		React.useImperativeHandle(forwardedRef, () => ref.current as HTMLDivElement);

		React.useEffect(() => {
			if (isInteracting.current) return;

			progress.set(valueToProgress(currentValue, min, max));
		}, [currentValue, max, min, progress]);

		const emitProgress = React.useCallback(
			(nextProgress: number, options: { commit?: boolean } = {}) => {
				const nextValue = progressToValue(nextProgress, min, max, step);

				if (controlledValue === undefined) {
					setUncontrolledValue(nextValue);
				}

				onValueChange?.([nextValue]);
				if (options.commit) {
					onValueCommit?.([nextValue]);
				}
			},
			[controlledValue, max, min, onValueChange, onValueCommit, step],
		);

		const setProgressFromClientX = React.useCallback(
			(clientX: number) => {
				const { left, right } = size.current;
				if (left === right) return;

				const nextProgress = inverted
					? calcProgress(right, left, clientX)
					: calcProgress(left, right, clientX);

				progress.set(nextProgress);
				emitProgress(nextProgress);
			},
			[emitProgress, inverted, progress],
		);

		const startInteraction = React.useCallback(
			(clientX: number) => {
				if (!ref.current) return;

				const { left, right } = ref.current.getBoundingClientRect();
				size.current = { left, right };
				initialDragX.current = clientX;
				initialProgressX.current = mix(left, right, inverted ? 1 - progress.get() : progress.get());
				isInteracting.current = true;
			},
			[inverted, progress],
		);

		const moveInteraction = React.useCallback(
			(clientX: number) => {
				const dragOffset = clientX - initialDragX.current;
				const nextProgressX = initialProgressX.current + dragOffset;
				setProgressFromClientX(nextProgressX);
			},
			[setProgressFromClientX],
		);

		const settleProgress = React.useCallback(() => {
			const finalProgress = progress.get();
			const clampedProgress = clamp(0, 1, finalProgress);

			if (finalProgress !== clampedProgress && !shouldReduceMotion) {
				animate(progress, clampedProgress, { type: "spring", ...SETTLE_SPRING });
			} else {
				progress.set(clampedProgress);
			}

			emitProgress(clampedProgress, { commit: true });
			isInteracting.current = false;
		}, [emitProgress, progress, shouldReduceMotion]);

		const handleKeyDown = React.useCallback(
			(event: React.KeyboardEvent<HTMLDivElement>) => {
				if (disabled) return;

				const keyStep = keyboardStep ?? step;
				let nextValue = currentValue;

				if (event.key === "ArrowRight" || event.key === "ArrowUp") {
					nextValue = currentValue + (inverted ? -keyStep : keyStep);
				} else if (event.key === "ArrowLeft" || event.key === "ArrowDown") {
					nextValue = currentValue + (inverted ? keyStep : -keyStep);
				} else if (event.key === "Home") {
					nextValue = inverted ? max : min;
				} else if (event.key === "End") {
					nextValue = inverted ? min : max;
				} else {
					return;
				}

				event.preventDefault();

				const nextProgress = max === min ? 0 : (nextValue - min) / (max - min);
				const clampedProgress = clamp(0, 1, nextProgress);
				const nextRoundedValue = progressToValue(clampedProgress, min, max, step);

				if (controlledValue === undefined) {
					setUncontrolledValue(nextRoundedValue);
				}

				onValueChange?.([nextRoundedValue]);
				onValueCommit?.([nextRoundedValue]);

				if (nextProgress > 1 && !shouldReduceMotion) {
					animate(progress, 1, { velocity: 20, type: "spring", ...keyboardSpring });
				} else if (nextProgress < 0 && !shouldReduceMotion) {
					animate(progress, 0, { velocity: -20, type: "spring", ...keyboardSpring });
				} else {
					progress.jump(clampedProgress);
				}
			},
			[
				controlledValue,
				currentValue,
				disabled,
				inverted,
				keyboardSpring,
				keyboardStep,
				max,
				min,
				onValueChange,
				onValueCommit,
				progress,
				shouldReduceMotion,
				step,
			],
		);

		return (
			<motion.div
				ref={ref}
				role="slider"
				tabIndex={disabled ? -1 : 0}
				aria-label={ariaLabel}
				aria-labelledby={ariaLabelledBy}
				aria-valuemin={min}
				aria-valuemax={max}
				aria-valuenow={currentValue}
				aria-orientation={orientation}
				aria-disabled={disabled}
				data-disabled={disabled ? "" : undefined}
				className={cn(
					"group/slider relative flex h-8 w-full min-w-0 touch-none select-none items-center overflow-visible outline-none",
					disabled && "pointer-events-none opacity-50",
					className,
				)}
				onPointerDown={(event) => {
					onPointerDownProp?.(event);
					if (disabled || event.defaultPrevented || event.button !== 0) return;

					event.currentTarget.setPointerCapture(event.pointerId);
					isPointerInteracting.current = true;
					didPointerSettle.current = false;
					startInteraction(event.clientX);
				}}
				onPointerMove={(event) => {
					onPointerMoveProp?.(event);
					if (disabled || event.defaultPrevented || !isPointerInteracting.current) return;

					moveInteraction(event.clientX);
				}}
				onPointerUp={(event) => {
					onPointerUpProp?.(event);
					if (disabled || event.defaultPrevented || !isPointerInteracting.current) return;

					event.currentTarget.releasePointerCapture(event.pointerId);
					isPointerInteracting.current = false;
					didPointerSettle.current = true;
					settleProgress();
				}}
				onPointerCancel={(event) => {
					onPointerCancelProp?.(event);
					if (disabled || !isPointerInteracting.current) return;

					event.currentTarget.releasePointerCapture(event.pointerId);
					isPointerInteracting.current = false;
					didPointerSettle.current = true;
					settleProgress();
				}}
				onTapStart={(event, info) => {
					onTapStartProp?.(event, info);
					if (disabled || !ref.current || event.defaultPrevented) return;

					startInteraction(getClientX(event));
				}}
				onPan={(event, info) => {
					onPanProp?.(event, info);
					if (disabled || event.defaultPrevented) return;

					moveInteraction(getClientX(event));
				}}
				onPanEnd={(event, info) => {
					onPanEndProp?.(event, info);
					if (disabled || event.defaultPrevented) return;
					if (didPointerSettle.current) {
						didPointerSettle.current = false;
						return;
					}

					settleProgress();
				}}
				onKeyDown={(event) => {
					onKeyDownProp?.(event);
					if (!event.defaultPrevented) {
						handleKeyDown(event);
					}
				}}
				style={style}
				{...props}
			>
				<motion.div
					className="relative h-4 w-full overflow-hidden rounded-full border border-white/10 bg-white/10 shadow-[inset_0_1px_1px_rgba(255,255,255,0.1),inset_0_-1px_2px_rgba(0,0,0,0.18)] transition-shadow duration-150 group-focus-visible/slider:shadow-[0_0_0_3px_rgba(37,99,235,0.35),inset_0_1px_1px_rgba(255,255,255,0.12)]"
					style={{ ...slider, x: translateX, scaleX, scaleY }}
					transition={{ duration: 0.15 }}
				>
					<motion.div
						style={{
							...indicator,
							originX: fillOrigin,
							scaleX: brightness,
						}}
					/>
				</motion.div>
			</motion.div>
		);
	},
);

Slider.displayName = "Slider";

const slider: MotionStyle = {
	touchAction: "none",
	willChange: "transform",
};

const indicator: MotionStyle = {
	position: "absolute",
	top: 0,
	left: 0,
	bottom: 0,
	right: 0,
	backgroundColor: "#f5f5f5",
	pointerEvents: "none",
};

export { Slider };
