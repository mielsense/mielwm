<script lang="ts">
	// A small tilted gradient tile with a white glyph, from miel.my. It springs upright when the
	// group/section around it is hovered.
	import Icon from '@/components/Icon.svelte';
	import type { IconData } from '@/icons';

	let { icon, bg, size = 24 }: { icon: IconData; bg: string; size?: number } = $props();
</script>

<span
	class="grain grid shrink-0 -rotate-6 place-items-center text-white shadow-[0_2px_6px_rgb(0_0_0/0.12)] transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover/section:rotate-3 group-hover/section:scale-110 motion-reduce:transition-none"
	style:background={bg}
	style:width="{size}px"
	style:height="{size}px"
	style:border-radius="{Math.round(size * 0.29)}px"
	aria-hidden="true"
>
	<Icon {icon} size={Math.round(size / 2)} />
</span>
