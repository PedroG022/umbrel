import {fileURLToPath} from 'node:url'
import {dirname, join} from 'node:path'

import {$} from 'execa'
import fse from 'fs-extra'

import type Umbreld from '../../../index.js'

export default async function appEnvironment(umbreld: Umbreld, command: string) {
	let inheritStdio = true
	// Prevent breaking test output
	if (process.env.TEST === 'true') inheritStdio = false

	const containerName = process.env.UMBREL_CONTAINER_NAME
	if (!containerName) throw new Error('Failed to determine the Umbrel container name.')

	const currentFilename = fileURLToPath(import.meta.url)
	const currentDirname = dirname(currentFilename)
	const composePath = join(currentDirname, 'docker-compose.yml')
	const torEnabled = await umbreld.store.get('torEnabled')
	let appDomainBase = process.env.APP_DOMAIN_BASE || ''
	let appEntrypoints = process.env.APP_ENTRYPOINTS || 'web'
	let appEnableTls = process.env.APP_ENABLE_TLS || 'false'

	try {
		const envPath = join(umbreld.dataDirectory, '.env')
		if (await fse.pathExists(envPath)) {
			const envContent = await fse.readFile(envPath, 'utf8')
			const opModeMatch = envContent.match(/^OPERATION_MODE=["']?([^"'\n]+)["']?/m)
			const opMode = opModeMatch ? opModeMatch[1] : '1'

			if (opMode === '1') {
				const localHostMatch = envContent.match(/^LOCAL_HOSTNAME=["']?([^"'\n]+)["']?/m)
				const localDomMatch = envContent.match(/^LOCAL_DOMAIN=["']?([^"'\n]+)["']?/m)
				const localHost = localHostMatch ? localHostMatch[1] : 'umbrel'
				const localDom = localDomMatch ? localDomMatch[1] : 'local'
				if (!appDomainBase) appDomainBase = `${localHost}.${localDom}`
				appEntrypoints = 'web'
				appEnableTls = 'false'
			} else if (opMode === '3') {
				const tsHostMatch = envContent.match(/^TAILSCALE_HOSTNAME=["']?([^"'\n]+)["']?/m)
				const tsNetMatch = envContent.match(/^TAILNET_NAME=["']?([^"'\n]+)["']?/m)
				if (!appDomainBase) {
					if (tsHostMatch && tsNetMatch && tsNetMatch[1]) {
						appDomainBase = `${tsHostMatch[1]}.${tsNetMatch[1].replace(/\.$/, '')}`
					} else if (tsHostMatch) {
						appDomainBase = tsHostMatch[1]
					}
				}
				appEntrypoints = 'web'
				appEnableTls = 'false'
			} else {
				const domainMatch = envContent.match(/^DOMAIN=["']?([^"'\n]+)["']?/m)
				const subdomainMatch = envContent.match(/^SUBDOMAIN=["']?([^"'\n]+)["']?/m)
				if (!appDomainBase) {
					if (domainMatch && subdomainMatch && subdomainMatch[1]) {
						appDomainBase = `${subdomainMatch[1]}.${domainMatch[1]}`
					} else if (domainMatch) {
						appDomainBase = domainMatch[1]
					}
				}
				appEntrypoints = 'websecure'
				appEnableTls = 'true'
			}
		}
	} catch (error) {
		// fallback
	}

	const options = {
		stdio: inheritStdio ? 'inherit' : 'pipe',
		cwd: umbreld.dataDirectory,
		env: {
			UMBREL_DATA_DIR: umbreld.dataDirectory,
			APP_DOMAIN_BASE: appDomainBase,
			APP_ENTRYPOINTS: appEntrypoints,
			APP_ENABLE_TLS: appEnableTls,
			ENABLE_TLS: appEnableTls,
			// TODO: Load these from somewhere more appropriate
			NETWORK_IP: '10.21.0.0',
			GATEWAY_IP: '10.21.0.1',
			DASHBOARD_IP: '10.21.21.3',
			MANAGER_IP: '10.21.21.4',
			AUTH_IP: '10.21.21.6',
			AUTH_PORT: '2000',
			TOR_PROXY_IP: '10.21.21.11',
			TOR_PROXY_PORT: '9050',
			TOR_PASSWORD: 'mLcLDdt5qqMxlq3wv8Din3UD44bTZHzRFhIktw38kWg=',
			TOR_HASHED_PASSWORD: '16:158FBE422B1A9D996073BE2B9EC38852C70CE12362CA016F8F6859C426',
			UMBREL_AUTH_SECRET: 'DEADBEEF', // Not used, just left in for compatibility reasons
			JWT_SECRET: await umbreld.server.getJwtSecret(),
			UMBRELD_RPC_HOST: `${containerName}:${umbreld.server.port}`,
			UMBREL_LEGACY_COMPAT_DIR: currentDirname,
			UMBREL_TORRC: torEnabled
				? `${umbreld.dataDirectory}/tor/tor-server-torrc`
				: `${umbreld.dataDirectory}/tor/tor-proxy-torrc`,
		},
	}

	if (command === 'up') {
		// Docker: Copy torrc files to data directory so they're accessible to tor containers
		await fse.copy(`${currentDirname}/tor-proxy-torrc`, `${umbreld.dataDirectory}/tor/tor-proxy-torrc`)
		await fse.copy(`${currentDirname}/tor-server-torrc`, `${umbreld.dataDirectory}/tor/tor-server-torrc`)
		await $(
			options as any,
		)`docker compose --project-name umbrelc --file ${composePath} ${command} --build --detach --remove-orphans`
	} else {
		await $(options as any)`docker compose --project-name umbrelc --file ${composePath} ${command}`
	}
}
