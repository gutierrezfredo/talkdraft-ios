// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	integrations: [
		starlight({
			title: 'Talkdraft',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/gutierrezfredo/talkdraft-ios' }],
			sidebar: [
				{ label: 'Overview', link: '/' },
				{ label: 'Getting Started', link: '/getting-started/' },
				{
					label: 'Architecture',
					items: [
						{ label: 'Overview', slug: 'architecture/overview' },
						{ label: 'Integrations', slug: 'architecture/integrations' },
						{ label: 'Transcription Pipeline', slug: 'architecture/transcription-pipeline' },
					],
				},
				{
					label: 'Views',
					items: [
						{ label: 'Home', slug: 'views/home' },
						{ label: 'Record', slug: 'views/record' },
						{ label: 'Note Detail', slug: 'views/note-detail' },
						{ label: 'Categories', slug: 'views/categories' },
						{ label: 'Settings', slug: 'views/settings' },
						{ label: 'Recently Deleted', slug: 'views/recently-deleted' },
						{ label: 'Authentication', slug: 'views/auth' },
						{ label: 'Paywall', slug: 'views/paywall' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Terminology', slug: 'reference/terminology' },
					],
				},
			],
		}),
	],
});
