/* eslint-disable @lwc/lwc/no-async-operation -- Carousel transition timer is cancelled during disconnect. */

import { LightningElement } from "lwc";
import basePath from "@salesforce/community/basePath";

import signature1 from "@salesforce/resourceUrl/gvSignature1";
import signature2 from "@salesforce/resourceUrl/gvSignature2";
import signature3 from "@salesforce/resourceUrl/gvSignature3";

import arrival1 from "@salesforce/resourceUrl/gvNewArrival1";
import arrival2 from "@salesforce/resourceUrl/gvNewArrival2";
import arrival3 from "@salesforce/resourceUrl/gvNewArrival3";

import bridal1 from "@salesforce/resourceUrl/gvBridal1";
import bridal2 from "@salesforce/resourceUrl/gvBridal2";
import bridal3 from "@salesforce/resourceUrl/gvBridal3";

const COLLECTIONS = [
  {
    id: "signature",
    title: "Signature Collection",
    description: "Extraordinary pieces for timeless elegance.",
    images: [signature1, signature2, signature3],
    path: "/collections?category=signature"
  },
  {
    id: "arrivals",
    title: "New Arrivals",
    description: "Discover our latest jewellery creations.",
    images: [arrival1, arrival2, arrival3],
    path: "/new-arrivals"
  },
  {
    id: "bridal",
    title: "Bridal Jewellery",
    description: "Celebrate forever with exceptional beauty.",
    images: [bridal1, bridal2, bridal3],
    path: "/collections?category=bridal"
  }
];

const HALF_DURATION = 350;

export default class GoldvueeCategoryCarousel extends LightningElement {
  indices = {
    signature: 0,
    arrivals: 0,
    bridal: 0
  };

  phases = {
    signature: "idle",
    arrivals: "idle",
    bridal: "idle"
  };

  timers = new Map();
  touchStartX = 0;

  get categories() {
    return COLLECTIONS.map((category) => {
      const id = category.id;
      const index = this.indices[id];
      const phase = this.phases[id];

      let animationClass = "gv-image-rotator";

      if (phase === "out") {
        animationClass += " gv-flip-out";
      } else if (phase === "in") {
        animationClass += " gv-flip-in";
      }

      return {
        ...category,
        currentImage: category.images[index],
        displayIndex: index + 1,
        totalImages: category.images.length,
        imageAlt: `${category.title} image ${index + 1}`,
        animationClass,
        isAnimating: phase !== "idle",
        url: `${basePath}${category.path}`
      };
    });
  }

  nextImage(event) {
    this.changeImage(event.currentTarget.dataset.id, 1);
  }

  previousImage(event) {
    this.changeImage(event.currentTarget.dataset.id, -1);
  }

  changeImage(id, direction) {
    const category = COLLECTIONS.find((item) => item.id === id);

    if (!category || this.phases[id] !== "idle") {
      return;
    }

    // First half: current image rotates away.
    this.phases = {
      ...this.phases,
      [id]: "out"
    };

    const timer = setTimeout(() => {
      const nextIndex =
        (this.indices[id] + direction + category.images.length) %
        category.images.length;

      // Change image at the midpoint.
      this.indices = {
        ...this.indices,
        [id]: nextIndex
      };

      // Second half: new image rotates into view.
      this.phases = {
        ...this.phases,
        [id]: "in"
      };

      this.timers.delete(id);
    }, HALF_DURATION);

    this.timers.set(id, timer);
  }

  handleAnimationEnd(event) {
    if (event.target !== event.currentTarget) {
      return;
    }

    const id = event.currentTarget.dataset.id;

    if (this.phases[id] === "in") {
      this.phases = {
        ...this.phases,
        [id]: "idle"
      };
    }
  }

  handleTouchStart(event) {
    this.touchStartX = event.touches[0].clientX;
  }

  handleTouchEnd(event) {
    const endX = event.changedTouches[0].clientX;
    const distance = endX - this.touchStartX;

    if (Math.abs(distance) < 50) {
      return;
    }

    const id = event.currentTarget.dataset.id;
    this.changeImage(id, distance < 0 ? 1 : -1);
  }

  disconnectedCallback() {
    this.timers.forEach((timer) => clearTimeout(timer));
    this.timers.clear();
  }
}
