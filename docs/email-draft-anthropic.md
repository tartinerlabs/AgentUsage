# Email Draft — Anthropic Outreach

**Subject:** ClaudeMeter — a usage monitor app for Claude Pro/Max (seeking guidance)

---

Hi there,

I'm building ClaudeMeter, a native SwiftUI app (macOS menu bar + iOS) that gives Claude Pro and Max subscribers a way to monitor their API usage in real-time — think usage windows, reset timers, token costs, home screen and lock screen widgets, and Live Activities on the Dynamic Island. It's built to feel like a first-party companion for Claude Code users.

Here's a quick look: [link to screenshots or GitHub repo]

Right now, the app authenticates using the local credentials that Claude Code creates and pulls usage data from your API. It works great, but I'm aware this isn't a public-facing API — not something I should be building a published product on without checking in first.

I'm planning to release ClaudeMeter on the App Store, and before I do, I wanted to reach out to ask:

1. **Is this okay?** Are you comfortable with a third-party app using this credential and endpoint, or would you prefer I hold off?
2. **Is a public usage API on the roadmap?** Even a simple read-only endpoint for Pro/Max subscribers to check their own usage would be a game-changer for tools like this.
3. **Anything I should be aware of?** If there are upcoming changes to the auth flow or usage endpoint that would affect this, I'd love a heads-up so I can adapt.

For what it's worth, the app is purely read-only — it never writes or modifies anything. I think giving subscribers better visibility into their usage is a net positive (I've personally found it really helpful for managing my own limits), and I'd love to build this on a stable foundation rather than hoping nothing breaks.

Happy to share a TestFlight build, walk through the code, or chat further if that's helpful.

Thanks for your time!

[Your name]
[Link to project / your site]
