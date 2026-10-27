/**
 * Frames for a dithered reveal: a front that spreads out from a point, drawn with a 4x4 ordered
 * (Bayer) dither so the new surface arrives in chunky pixels instead of a smooth edge.
 *
 * Each frame is a small SVG used as a mask: concentric rings, each filled with the dither pattern
 * at the density its distance calls for. It is vector, so the pixels stay crisp at any size.
 */

// 4x4 Bayer matrix: the order in which the 16 cells of a tile switch on.
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const LEVELS = 16;

/** A tile pattern with the first `level` cells (in Bayer order) on. */
function pattern(level: number, cell: number) {
	let rects = '';
	BAYER.forEach((rank, i) => {
		if (rank < level) rects += `<rect x="${(i % 4) * cell}" y="${Math.floor(i / 4) * cell}" width="${cell}" height="${cell}"/>`;
	});
	return `<pattern id="p${level}" width="${cell * 4}" height="${cell * 4}" patternUnits="userSpaceOnUse">${rects}</pattern>`;
}

/** Dither density (0 to 16) at normalized distance `d` when the reveal is `progress` of the way. */
export function levelAt(d: number, progress: number, band: number) {
	const front = progress * (1 + band);
	return Math.max(0, Math.min(LEVELS, Math.round(((front - d) / band) * LEVELS)));
}

export function ditherFrames(from: { x: number; y: number }, width: number, height: number, { frames = 20, rings = 14, cell = 5, band = 0.45 } = {}) {
	const reach = Math.hypot(Math.max(from.x, width - from.x), Math.max(from.y, height - from.y));
	const defs = Array.from({ length: LEVELS - 1 }, (_, i) => pattern(i + 1, cell)).join('');

	return Array.from({ length: frames + 1 }, (_, f) => {
		const progress = f / frames;
		let shapes = '';
		// outermost ring first, so each smaller circle paints over the one around it
		for (let r = rings; r >= 1; r--) {
			const level = levelAt((r - 0.5) / rings, progress, band);
			if (level === 0) continue;
			const fill = level >= LEVELS ? '#000' : `url(#p${level})`;
			shapes += `<circle cx="${from.x}" cy="${from.y}" r="${(r / rings) * reach}" fill="${fill}"/>`;
		}
		const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" shape-rendering="crispEdges"><defs>${defs}</defs>${shapes}</svg>`;
		return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
	});
}
