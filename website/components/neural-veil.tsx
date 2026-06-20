"use client";

import { useEffect, useRef } from "react";

export function NeuralVeil() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    const context = canvas?.getContext("2d");
    if (!canvas || !context) return;
    let frame = 0, width = 0, height = 0, pointerX = .68, pointerY = .28;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const resize = () => {
      const ratio = Math.min(window.devicePixelRatio, 2);
      width = canvas.clientWidth; height = canvas.clientHeight;
      canvas.width = width * ratio; canvas.height = height * ratio;
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
    };
    const move = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointerX = (event.clientX - rect.left) / rect.width;
      pointerY = (event.clientY - rect.top) / rect.height;
    };
    const paint = (time = 0) => {
      context.clearRect(0, 0, width, height); context.fillStyle = "#08070b"; context.fillRect(0, 0, width, height);
      const t = time * .00025;
      context.save(); context.filter = `blur(${Math.max(28, width * .035)}px)`; context.globalCompositeOperation = "screen";
      [
        { color: "rgba(108,42,255,.82)", y: .15, amp: .17, speed: 1 },
        { color: "rgba(176,42,255,.62)", y: .28, amp: .13, speed: -.72 },
        { color: "rgba(93,219,255,.42)", y: .09, amp: .1, speed: .48 },
      ].forEach((ribbon, index) => {
        context.beginPath(); context.moveTo(-width * .1, -height * .05);
        for (let x = -width * .1; x <= width * 1.1; x += Math.max(22, width / 45)) {
          const nx = x / width;
          const pull = Math.exp(-Math.pow(nx - pointerX, 2) / .05) * (pointerY - .25) * .22;
          context.lineTo(x, height * (ribbon.y + Math.sin(nx * 5.2 + t * ribbon.speed + index) * ribbon.amp + pull));
        }
        context.lineTo(width * 1.1, height * .62); context.lineTo(-width * .1, height * .48); context.closePath();
        const gradient = context.createLinearGradient(0, 0, width, height * .4);
        gradient.addColorStop(0, "rgba(20,8,44,.06)"); gradient.addColorStop(.28, ribbon.color); gradient.addColorStop(.72, ribbon.color); gradient.addColorStop(1, "rgba(5,3,18,.02)");
        context.fillStyle = gradient; context.fill();
      });
      context.restore();
      const shade = context.createLinearGradient(0, 0, 0, height);
      shade.addColorStop(0, "rgba(7,6,10,.02)"); shade.addColorStop(.52, "rgba(7,7,7,.52)"); shade.addColorStop(1, "#080807");
      context.fillStyle = shade; context.fillRect(0, 0, width, height);
      if (!reduced) frame = requestAnimationFrame(paint);
    };
    resize(); paint(); window.addEventListener("resize", resize); canvas.addEventListener("pointermove", move);
    return () => { cancelAnimationFrame(frame); window.removeEventListener("resize", resize); canvas.removeEventListener("pointermove", move); };
  }, []);
  return <canvas ref={canvasRef} className="absolute inset-0 size-full" aria-hidden="true"/>;
}
