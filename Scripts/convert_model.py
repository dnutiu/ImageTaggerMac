"""
Converts the ImageTagger ONNX model (from the AIModels release of
https://github.com/dnutiu/ImageTagger) into a Core ML classifier.

The converted model:
  * takes a 224x224 RGB image and normalizes it with the ImageNet mean/std,
  * outputs a sigmoid probability per tag (multi-label classification),
  * embeds the tag names, so no separate categories file is needed.

Usage:
  python3 -m venv .venv && .venv/bin/pip install -r Scripts/requirements.txt
  .venv/bin/python Scripts/convert_model.py \
      --onnx prediction.onnx \
      --labels prediction_categories.txt \
      --output ImageTagger/Resources/TagPrediction.mlpackage
"""
import argparse

import coremltools as ct
import onnx
import torch
from onnx2torch import convert


class Tagger(torch.nn.Module):
    """Wraps the ResNet network with input normalization and a sigmoid output."""

    def __init__(self, network):
        super().__init__()
        self.network = network
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

    def forward(self, image):
        return torch.sigmoid(self.network((image - self.mean) / self.std))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--onnx", required=True, help="Path to prediction.onnx")
    parser.add_argument("--labels", required=True, help="Path to prediction_categories.txt")
    parser.add_argument("--output", required=True, help="Output .mlpackage path")
    args = parser.parse_args()

    with open(args.labels) as labels_file:
        labels = [line.strip() for line in labels_file if line.strip()]

    model = Tagger(convert(onnx.load(args.onnx))).eval()
    traced = torch.jit.trace(model, torch.rand(1, 3, 224, 224))

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(name="image", shape=(1, 3, 224, 224), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)
        ],
        classifier_config=ct.ClassifierConfig(labels),
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
    )

    mlmodel.author = "Denis-Cosmin Nutiu"
    mlmodel.license = "GPL-3.0"
    mlmodel.version = "1.0"
    mlmodel.short_description = f"Predicts keyword tags for photos. ResNet based multi-label classifier, {len(labels)} tags."
    mlmodel.input_description["image"] = "Photo to tag. Center-cropped and scaled to 224x224."
    mlmodel.output_description["classLabel"] = "Most likely tag."
    mlmodel.output_description["classLabel_probs"] = "Probability of each tag. Tags above 0.3775 are reported."
    mlmodel.save(args.output)
    print(f"Saved {args.output} with {len(labels)} tags.")


if __name__ == "__main__":
    main()
