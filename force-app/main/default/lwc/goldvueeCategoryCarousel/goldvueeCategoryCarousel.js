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

export default class GoldvueeCategoryCarousel extends LightningElement {
  indices = {
    signature: 0,
    arrivals: 0,
    bridal: 0
  };

  pendingIndices = {
    signature: 1,
    arrivals: 1,
    bridal: 1
  };

  flipping = {
    signature: false,
    arrivals: false,
    bridal: false
  };

  touchStartX = 0;

  // Prepare current and upcoming images
  get categories() {
    return COLLECTIONS.map((category) => {
      const id = category.id;
      const index = this.indices[id];
      const pendingIndex = this.pendingIndices[id];
      const isAnimating = this.flipping[id];

      return {
        ...category,

        currentImage: category.images[index],

        upcomingImage: category.images[pendingIndex],

        displayIndex: index + 1,

        totalImages: category.images.length,

        imageAlt: `${category.title} image ${index + 1}`,

        animationClass: isAnimating
          ? "gv-image-rotator gv-flipping"
          : "gv-image-rotator",

        isAnimating,

        url: `${basePath}${category.path}`
      };
    });
  }

  // Next image
  nextImage(event) {
    const id = event.currentTarget.dataset.id;
    this.changeImage(id, 1);
  }

  // Previous image
  previousImage(event) {
    const id = event.currentTarget.dataset.id;
    this.changeImage(id, -1);
  }

  // Start continuous 180 degree flip
  changeImage(id, direction) {
    const category = COLLECTIONS.find((item) => item.id === id);

    if (!category || this.flipping[id]) {
      return;
    }

    const currentIndex = this.indices[id];

    const nextIndex =
      (currentIndex + direction + category.images.length) %
      category.images.length;

    // Prepare image on the back face
    this.pendingIndices = {
      ...this.pendingIndices,
      [id]: nextIndex
    };

    // Start one continuous flip animation
    this.flipping = {
      ...this.flipping,
      [id]: true
    };
  }

  // Flip completed
  handleAnimationEnd(event) {
    if (event.target !== event.currentTarget) {
      return;
    }

    const id = event.currentTarget.dataset.id;

    if (!this.flipping[id]) {
      return;
    }

    // Commit next image as current image
    this.indices = {
      ...this.indices,
      [id]: this.pendingIndices[id]
    };

    // Reset rotation for next interaction
    this.flipping = {
      ...this.flipping,
      [id]: false
    };
  }

  // Mobile swipe support
  handleTouchStart(event) {
    if (!event.touches.length) {
      return;
    }

    this.touchStartX = event.touches[0].clientX;
  }

  handleTouchEnd(event) {
    if (!event.changedTouches.length) {
      return;
    }

    const endX = event.changedTouches[0].clientX;

    const distance = endX - this.touchStartX;

    if (Math.abs(distance) < 50) {
      return;
    }

    const id = event.currentTarget.dataset.id;

    this.changeImage(id, distance < 0 ? 1 : -1);
  }
}
