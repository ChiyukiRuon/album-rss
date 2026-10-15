import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { RemoteEntry, Snapshot } from '@album-rss/core'

const mocks = vi.hoisted(() => ({
  authenticate: vi.fn(),
  snapshot: vi.fn(),
  setRead: vi.fn(),
  setStarred: vi.fn(),
}))
vi.mock('@album-rss/providers', async (load) => ({
  ...(await load<typeof import('@album-rss/providers')>()),
  createProvider: () => mocks,
}))
vi.mock('../lib/parseEntry', () => ({
  parseEntry: (entry: RemoteEntry) => ({
    ...entry,
    images: [],
    paragraphs: [],
    parseState: 'none',
  }),
}))

function snapshot(): Snapshot {
  return {
    feeds: [],
    folders: [],
    entries: [
      {
        id: '1',
        feedId: '2',
        title: 'Article',
        author: '',
        url: 'https://example.com/post',
        publishedAt: 1,
        content: '',
        enclosures: [],
        tags: [],
        read: false,
        starred: false,
      },
    ],
  }
}
function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: Error) => void
  const promise = new Promise<T>((yes, no) => {
    resolve = yes
    reject = no
  })
  return { promise, resolve, reject }
}
const input = {
  service: 'miniflux' as const,
  server: 'https://example.com/rss/',
  username: '',
  remember: false,
  apiKey: 'token',
  password: 'never-persist-this',
}

beforeEach(() => {
  vi.resetModules()
  vi.resetAllMocks()
  vi.useFakeTimers()
  const saved = new Map<string, string>()
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => saved.get(key) ?? null,
    setItem: (key: string, value: string) => saved.set(key, value),
    removeItem: (key: string) => saved.delete(key),
  })
  vi.stubGlobal('window', { setTimeout })
  mocks.authenticate.mockResolvedValue('reader')
  mocks.snapshot.mockImplementation(async () => snapshot())
  mocks.setRead.mockResolvedValue(undefined)
  mocks.setStarred.mockResolvedValue(undefined)
})
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('connected app state', () => {
  it('adds, edits, switches and removes endpoints while persisting only remembered credentials', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect({ ...input, remember: true, name: 'First' })
    const first = appStore.get().session!
    actions.setRead(['1'], true)
    await actions.connect({ ...input, server: 'https://second.example.com', name: 'Second' })
    const second = appStore.get().session!
    expect(appStore.get().endpoints).toHaveLength(2)
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(JSON.parse(localStorage.getItem('album-rss:endpoints')!)).toHaveLength(1)
    await actions.connect({ ...input, id: second.id, name: 'Edited' })
    expect(appStore.get().endpoints).toHaveLength(2)
    expect(appStore.get().session?.name).toBe('Edited')
    await actions.switchEndpoint(first.id!)
    expect(appStore.get().session?.id).toBe(first.id)
    expect(appStore.get().viewerSequence).toBeNull()
    actions.removeEndpoint(second.id!)
    expect(appStore.get().endpoints).toHaveLength(1)
    actions.signOut()
    expect(localStorage.getItem('album-rss:endpoints')).toBeNull()
  })

  it('keeps the active endpoint and pending writes intact when a switch fails', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const original = appStore.get().session
    const writing = deferred<void>()
    mocks.setRead.mockReturnValueOnce(writing.promise)
    actions.setRead(['1'], true)
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(1))
    mocks.snapshot.mockRejectedValueOnce(new Error('offline'))
    await expect(
      actions.connect({ ...input, server: 'https://offline.example.com' }),
    ).rejects.toThrow('offline')
    expect(appStore.get().session).toBe(original)
    expect(appStore.get().endpoints).toHaveLength(1)
    writing.reject(new Error('write failed'))
    await vi.waitFor(() => expect(appStore.get().entries['1']?.read).toBe(false))
  })

  it('migrates a remembered legacy connection and restores multiple endpoints on reload', async () => {
    localStorage.setItem(
      'album-rss:session',
      JSON.stringify({
        kind: 'connected',
        ...input,
        token: input.apiKey,
        remember: true,
      }),
    )
    const { actions, appStore } = await import('./store')
    const firstId = appStore.get().session?.id
    expect(firstId).toBeTruthy()
    await actions.connect({ ...input, remember: true, server: 'https://second.example.com' })
    vi.resetModules()
    const restored = await import('./store')
    expect(restored.appStore.get().endpoints).toHaveLength(2)
    expect(restored.appStore.get().endpoints[0]?.id).toBe(firstId)
    expect(restored.appStore.get().loaded).toBe(false)
  })

  it('ignores a previous endpoint snapshot even when both services use the same article IDs', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const reading = deferred<Snapshot>()
    mocks.snapshot.mockReturnValueOnce(reading.promise)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.snapshot).toHaveBeenCalledTimes(2))
    await actions.connect({ ...input, server: 'https://second.example.com' })
    const stale = snapshot()
    stale.entries[0]!.read = true
    reading.resolve(stale)
    await syncing
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(appStore.get().sync.status).toBe('idle')
  })

  it('replaces demo articles and persists only the explicitly remembered token', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    expect(appStore.get().order).toEqual(['1'])
    expect(localStorage.getItem('album-rss:session')).toBeNull()
    await actions.connect({ ...input, remember: true })
    const saved = localStorage.getItem('album-rss:session')!
    expect(JSON.parse(saved)).toMatchObject({
      token: 'token',
      server: 'https://example.com/rss',
      username: 'reader',
    })
    expect(saved).not.toContain(input.password)
    actions.signOut()
    expect(localStorage.getItem('album-rss:session')).toBeNull()
    expect(appStore.get().order).toEqual([])
    actions.enterDemo()
    expect(appStore.get().order.length).toBeGreaterThan(1)
  })

  it('does not establish a session after a failed initial sync', async () => {
    const { actions, appStore } = await import('./store')
    mocks.snapshot.mockRejectedValueOnce(new Error('offline'))
    await expect(actions.connect(input)).rejects.toThrow('offline')
    expect(appStore.get().session).toBeNull()
    expect(localStorage.getItem('album-rss:session')).toBeNull()
  })

  it('serializes rapid writes and rolls back consecutive failures to confirmed state', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const first = deferred<void>()
    const second = deferred<void>()
    mocks.setRead.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise)
    actions.setRead(['1'], true)
    actions.setRead(['1'], false)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(1))
    first.reject(new Error('offline'))
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledTimes(2))
    second.reject(new Error('offline'))
    mocks.snapshot.mockImplementationOnce(async () => {
      expect(appStore.get().entries['1']?.read).toBe(false)
      return snapshot()
    })
    await syncing
    expect(appStore.get().entries['1']?.read).toBe(false)
  })

  it('keeps a local change made while a snapshot is in flight', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const reading = deferred<Snapshot>()
    mocks.snapshot.mockReturnValueOnce(reading.promise)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.snapshot).toHaveBeenCalledTimes(2))
    actions.setStarred('1', true)
    await vi.waitFor(() => expect(mocks.setStarred).toHaveBeenCalledTimes(1))
    reading.resolve(snapshot())
    await syncing
    expect(appStore.get().entries['1']?.starred).toBe(true)
  })

  it('ignores stale sync responses after sign-out', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    const reading = deferred<Snapshot>()
    mocks.snapshot.mockReturnValueOnce(reading.promise)
    const syncing = actions.sync({ explicit: true })
    await vi.waitFor(() => expect(mocks.snapshot).toHaveBeenCalledTimes(2))
    actions.signOut()
    reading.resolve(snapshot())
    await syncing
    expect(appStore.get().session).toBeNull()
    expect(appStore.get().order).toEqual([])
  })

  it('retains earlier data when sync fails and clears the error on retry', async () => {
    const { actions, appStore } = await import('./store')
    await actions.connect(input)
    mocks.snapshot.mockRejectedValueOnce(new Error('offline'))
    await actions.sync({ explicit: true })
    expect(appStore.get().order).toEqual(['1'])
    expect(appStore.get().sync.error).toBe('offline')
    await actions.sync({ explicit: true })
    expect(appStore.get().sync.error).toBeUndefined()
  })

  it('does not mix a pending demo sync into a newly connected account', async () => {
    const { actions, appStore } = await import('./store')
    actions.enterDemo()
    const syncing = actions.sync({ explicit: true })
    await actions.connect(input)
    await vi.advanceTimersByTimeAsync(1000)
    await syncing
    expect(appStore.get().order).toEqual(['1'])
    expect(appStore.get().session?.kind).toBe('connected')
  })
})

describe('download read setting', () => {
  async function setup() {
    const store = await import('./store')
    await store.actions.connect(input)
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockImplementation(async () => new Response(new Blob(['image'], { type: 'image/png' }))),
    )
    vi.stubGlobal('document', { createElement: () => ({ click: vi.fn() }) })
    return {
      ...store,
      entry: store.appStore.get().entries['1']!,
      images: [{ key: 'image', url: 'https://example.com/image.png' }],
    }
  }

  it('defaults to marking successful downloads read and writes the state to the provider', async () => {
    const { actions, appStore, entry, images } = await setup()
    expect(appStore.get().settings.downloadRead).toBe(true)
    await actions.download('download', entry, images)
    expect(appStore.get().entries['1']?.read).toBe(true)
    await vi.waitFor(() => expect(mocks.setRead).toHaveBeenCalledWith(['1'], true))
  })

  it('persists the disabled preference and leaves successful downloads unread', async () => {
    const { actions, appStore, entry, images } = await setup()
    actions.updateSettings({ downloadRead: false })
    await actions.download('download', entry, images)
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(mocks.setRead).not.toHaveBeenCalled()
    expect(JSON.parse(localStorage.getItem('album-rss:settings')!).downloadRead).toBe(false)
  })

  it('leaves partial, failed and empty downloads unread', async () => {
    const { actions, appStore, entry, images } = await setup()
    vi.mocked(fetch).mockRejectedValueOnce(new Error('offline'))
    await actions.download('failed', entry, images)
    expect(appStore.get().downloads.failed?.status).toBe('blocked')
    vi.mocked(fetch)
      .mockResolvedValueOnce(new Response(new Blob(['image'], { type: 'image/png' })))
      .mockRejectedValueOnce(new Error('offline'))
    await actions.download('partial', entry, [...images, ...images])
    expect(appStore.get().downloads.partial).toMatchObject({ status: 'blocked', done: 1 })
    await actions.download('empty', entry, [])
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(mocks.setRead).not.toHaveBeenCalled()
  })

  it('does not mark the new endpoint read when an old download finishes', async () => {
    const { actions, appStore, entry, images } = await setup()
    const response = deferred<Response>()
    vi.mocked(fetch).mockReturnValueOnce(response.promise)
    const downloading = actions.download('old', entry, images)
    await actions.connect({ ...input, server: 'https://second.example.com' })
    response.resolve(new Response(new Blob(['image'], { type: 'image/png' })))
    await downloading
    expect(appStore.get().entries['1']?.read).toBe(false)
    expect(appStore.get().downloads).toEqual({})
    expect(mocks.setRead).not.toHaveBeenCalled()
  })
})
