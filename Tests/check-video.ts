import { join } from "node:path";

const root = join(import.meta.dir, "..");
const path = join(root, "SpaceX-4K-Loop.mp4");
const probe = Bun.spawnSync(["ffprobe", "-v", "error", "-show_entries",
  "format=duration:stream=codec_name,width,height,r_frame_rate,nb_frames", "-of", "json", path]);
if (probe.exitCode !== 0) throw new Error(probe.stderr.toString());
const metadata = JSON.parse(probe.stdout.toString());
const decoded = Bun.spawnSync(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
  "-vf", "select='eq(n,0)+eq(n,1499)',scale=64:36,format=gray",
  "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"]);
if (decoded.exitCode !== 0) throw new Error(decoded.stderr.toString());
const data = decoded.stdout;
const count = 64 * 36;
if (data.length !== count * 2) throw new Error("Expected two boundary frames");
let delta = 0, mean = 0;
for (let i = 0; i < count; i++) { delta += Math.abs(data[i] - data[count + i]); mean += data[i]; }
const video = metadata.streams[0];
const checks = {
  resolution: video.width === 3840 && video.height === 2160,
  duration: Number(metadata.format.duration) === 50,
  frames: Number(video.nb_frames) === 1500,
  frameRate: video.r_frame_rate === "30/1",
  noAudio: metadata.streams.length === 1,
  seamContinuity: delta / count < 2,
  notBlack: mean / count > 20,
};
const result = { checks, passed: Object.values(checks).every(Boolean),
  boundaryMeanAbsoluteDifference: delta / count, firstFrameMeanLuma: mean / count, metadata };
await Bun.write(join(import.meta.dir, "video.json"), JSON.stringify(result, null, 2));
console.log(result);
if (!result.passed) process.exit(1);
