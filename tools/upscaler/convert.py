# Converts Real-ESRGAN's compact general model (BSD-3) to a Core ML package for Grade.
# Input: a 256x256 RGB image. Output: the 1024x1024 upscaled image.
import sys, torch, coremltools as ct
sys.path.insert(0, "tools")
from srvgg import load

class Wrapper(torch.nn.Module):
    def __init__(self, net):
        super().__init__()
        self.net = net
    def forward(self, x):
        # x arrives as 0...1 (ImageType scale 1/255); return 0...255 for the image output.
        return self.net(x).clamp(0, 1) * 255

TILE = 256
model = Wrapper(load("weights/realesr-general-x4v3.pth")).eval()
traced = torch.jit.trace(model, torch.rand(1, 3, TILE, TILE))
ml = ct.convert(
    traced,
    inputs=[ct.ImageType(name="image", shape=(1, 3, TILE, TILE), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
    outputs=[ct.ImageType(name="upscaled", color_layout=ct.colorlayout.RGB)],
    minimum_deployment_target=ct.target.iOS17,
    convert_to="mlprogram",
    compute_precision=ct.precision.FLOAT16,
)
ml.short_description = "Real-ESRGAN general x4 (v3), 256 px tiles. BSD-3-Clause, (c) Xintao Wang."
ml.author = "Xintao Wang et al. (Real-ESRGAN)"
ml.license = "BSD-3-Clause"
ml.save(sys.argv[1])
