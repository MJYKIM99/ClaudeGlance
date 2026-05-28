# Desktop Pet Theme Guide

This guide explains how to ask Codex to add a new Claude Glance desktop pet
theme at the same quality bar as the built-in Pixel Robot, Orange Pixel Crab,
and White Pixel Polar Bear themes.

## What To Ask For

Use this prompt when you want Codex to implement a new theme end to end:

```text
In the ClaudeGlance repo, add a new desktop pet theme named <Theme Display Name>.

Requirements:
- Use imagegen to create a pixel-art sprite atlas for the theme.
- The atlas must be exactly 5 rows x 8 columns, 40 total frames.
- Rows, top to bottom:
  1. idle
  2. coding
  3. change/editing files
  4. request/waiting for user input
  5. report/completed work
- Each row must be an 8-frame smooth loop, not duplicated still frames.
- Generate on a flat chroma-key background, remove the background locally, and
  save transparent PNG frames into Assets.xcassets.
- Add the theme to AgentPetTheme so it appears in the menu and right-click pet
  settings.
- Keep the existing 8-frame playback model and menu behavior.
- Validate asset coverage and run a Release build.

Do not push to remote git. Keep all git work local.
```

Replace `<Theme Display Name>` with something concrete, for example:

```text
Blue Pixel Penguin
```

## Imagegen Prompt Template

Codex should use a prompt like this for the image generation step:

```text
Use case: stylized-concept
Asset type: macOS desktop pet sprite atlas, pixel art animation frames
Primary request: Create a single sprite atlas for a cute <theme description>
desktop companion. The atlas must contain exactly 5 rows and exactly 8 columns,
for 40 total frames. Each frame is a separate animation cel centered in its own
invisible square cell with generous padding.

Scene/backdrop: perfectly flat solid #00ff00 chroma-key background for
background removal. The background must be one uniform color with no shadows,
gradients, texture, reflections, floor plane, or lighting variation.

Subject: <specific mascot description>. Keep the same character proportions
across all 40 frames. The character must be readable at 128x128.

Rows, top to bottom:
row 1 idle loop with breathing, blinking, and tiny secondary motion;
row 2 coding loop with tiny laptop or keyboard and typing motion;
row 3 editing/changing files loop with file tiles and a small tool;
row 4 request loop with raised hand/paw/claw and alert body language, no text or
symbol glyphs;
row 5 report loop with cheerful completed-work posture and chart/paper prop, no
text.

Columns, left to right: eight sequential frames of the row's animation, smooth
loop, no duplicate stills.

Style: high-quality pixel art, game sprite atlas, chunky pixels, limited
palette, crisp opaque edges, no antialias blur, consistent lighting and scale.

Constraints: no text, no letters, no numbers, no visible grid lines, no question
mark symbols, no exclamation symbols, no watermark, no cast shadow, no contact
shadow, no reflection. Do not use #00ff00 anywhere in the character or props.
Keep each frame separated from the chroma background with crisp edges.
```

If the mascot is green or uses colors close to `#00ff00`, ask Codex to use
`#ff00ff` as the chroma key instead.

## Repository Touch Points

A new theme usually touches these areas:

- `ClaudeGlance/Models/AgentPetTheme.swift`
  Add a new enum case, display name, and asset prefix.
- `ClaudeGlance/Assets.xcassets/AgentPet<Theme>*.imageset/`
  Add transparent runtime frames and optional atlas/source images.
- `README.md`
  Update the theme list if the theme is user-facing.

The renderer already expects this naming pattern:

```text
AgentPet<ThemePrefix><Pose><FrameIndex>
```

Examples:

```text
AgentPetCrabCoding0
AgentPetPolarBearReport7
AgentPetPenguinIdle3
```

Poses must be named:

```text
Idle
Coding
Change
Request
Report
```

Frame indexes should be `0` through `7`.

## Quality Checklist

Before marking the work complete, Codex should verify:

- The generated atlas visibly contains 5 rows x 8 columns.
- Every state has real motion across 8 frames.
- The background has been removed and runtime frames have alpha.
- No frame contains obvious neighboring-cell fragments.
- The theme has 40 runtime frame imagesets.
- `Contents.json` points to the intended PNG in every imageset.
- The theme appears in the menu and desktop pet right-click menu.
- `git diff --check` passes.
- `xcodebuild -scheme ClaudeGlance -configuration Release -quiet` exits 0.

Useful verification commands:

```bash
node -e "const fs=require('fs');const path=require('path');const root='ClaudeGlance/Assets.xcassets';const theme='AgentPet<ThemePrefix>';const poses=['Idle','Coding','Change','Request','Report'];let missing=[];for(const pose of poses){for(let i=0;i<8;i++){const dir=path.join(root,theme+pose+i+'.imageset');if(!fs.existsSync(path.join(dir,'Contents.json'))) missing.push(theme+pose+i);}}if(missing.length){console.error(missing);process.exit(1);}console.log('runtime frame catalogs ok',poses.length*8);"
```

```bash
git diff --check
```

```bash
xcodebuild -scheme ClaudeGlance -configuration Release -quiet
```

## Example User Prompt

```text
给 ClaudeGlance 新增一个蓝色像素企鹅桌宠主题。请用 imagegen 生成 5 行 x 8 列
sprite atlas，包含 idle、coding、change、request、report 五个状态。去背景后切成
透明 PNG 帧，加入 Assets.xcassets，并把主题接入 AgentPetTheme、菜单和右键桌宠设置。
验证 40 个 runtime frames 都存在，并跑 Release build。只提交本地 git，不要 push。
```
