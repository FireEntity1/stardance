import { Controller } from "@hotwired/stimulus";

const STORAGE_KEY = "stardance.audioPlayer";

export default class extends Controller {
  static targets = ["audio", "toggle", "volume"];

  connect() {
    const settings = this.settings;
    const volume = settings.volume ?? 0.25;

    this.audioTarget.volume = volume;
    this.volumeTarget.value = volume;
    this.audioTarget.muted = settings.muted ?? false;

    this.sync();

    if (settings.playing) {
      this.play();
    }
  }

  toggle() {
    if (this.audioTarget.paused) {
      this.play();
    } else {
      this.pause();
    }
  }

  setVolume() {
    const volume = Number.parseFloat(this.volumeTarget.value);

    this.audioTarget.volume = volume;
    this.audioTarget.muted = volume === 0;
    this.persist({ volume, muted: this.audioTarget.muted });
    this.sync();
  }

  play() {
    this.audioTarget
      .play()
      .then(() => {
        this.persist({ playing: true });
        this.sync();
      })
      .catch(() => {
        this.persist({ playing: false });
        this.sync();
      });
  }

  pause() {
    this.audioTarget.pause();
    this.persist({ playing: false });
    this.sync();
  }

  sync() {
    const playing = !this.audioTarget.paused;
    this.element.classList.toggle("audio-player--playing", playing);
    this.toggleTarget.setAttribute("aria-pressed", playing.toString());
    this.toggleTarget.setAttribute(
      "aria-label",
      playing ? "Pause Stardance audio" : "Play Stardance audio",
    );
  }

  get settings() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {};
    } catch {
      return {};
    }
  }

  persist(nextSettings) {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ ...this.settings, ...nextSettings }),
    );
  }
}
