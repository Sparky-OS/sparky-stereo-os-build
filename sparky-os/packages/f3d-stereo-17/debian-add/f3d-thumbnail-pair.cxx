// f3d-thumbnail-pair PLUGIN SIZE INPUT OUTPUT
// A freedesktop thumbnailer (the %s, %i and %o of the .thumbnailer files) that draws a model as a
// stereo pair through libf3d: two parallel cameras, the left eye in the left half of the picture
// and the right eye in the right half, each eye SIZE/2 by SIZE/2 pixels (a picture of SIZE by SIZE/2), marked with the key the
// file managers of Sparky Stereo OS read (X-KDE::Stereo3DLayout). A screen without 3D shows the
// left half.
// SPDX-License-Identifier: BSD-3-Clause
#include <f3d/camera.h>
#include <f3d/engine.h>
#include <f3d/image.h>
#include <f3d/options.h>
#include <f3d/scene.h>
#include <f3d/window.h>

#include <zlib.h>

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <vector>
#include <exception>
#include <stdexcept>
#include <iostream>
#include <string>

// The PNG writer of libf3d keeps no text chunk, so the key goes in here, after the header chunk
// (PNG 1.2, 11.3.4.3 tEXt: keyword, a null separator, the text)
static std::vector<unsigned char> withText(const std::vector<unsigned char>& png, const std::string& key,
  const std::string& value)
{
  const size_t afterHeader = 8 + 4 + 4 + 13 + 4;
  if (png.size() < afterHeader)
  {
    return png;
  }
  std::vector<unsigned char> chunk;
  std::string body = "tEXt" + key + std::string(1, '\0') + value;
  const uint32_t length = static_cast<uint32_t>(body.size() - 4);
  for (int shift = 24; shift >= 0; shift -= 8)
  {
    chunk.push_back(static_cast<unsigned char>((length >> shift) & 0xff));
  }
  chunk.insert(chunk.end(), body.begin(), body.end());
  const uint32_t crc = crc32(0L, reinterpret_cast<const unsigned char*>(body.data()), static_cast<uInt>(body.size()));
  for (int shift = 24; shift >= 0; shift -= 8)
  {
    chunk.push_back(static_cast<unsigned char>((crc >> shift) & 0xff));
  }
  std::vector<unsigned char> out(png.begin(), png.begin() + afterHeader);
  out.insert(out.end(), chunk.begin(), chunk.end());
  out.insert(out.end(), png.begin() + afterHeader, png.end());
  return out;
}

int main(int argc, char** argv)
{
  if (argc != 5)
  {
    std::cerr << "usage: f3d-thumbnail-pair PLUGIN SIZE INPUT OUTPUT" << std::endl;
    return 2;
  }
  const std::string plugin = argv[1];
  const int size = std::atoi(argv[2]);
  if (size < 16 || size > 4096)
  {
    std::cerr << "f3d-thumbnail-pair: size " << argv[2] << " is not between 16 and 4096" << std::endl;
    return 2;
  }
  try
  {
    f3d::engine::autoloadPlugins();
    if (plugin != "all")
    {
      f3d::engine::loadPlugin(plugin);
    }
    f3d::engine engine = f3d::engine::create(true);
    f3d::options& opt = engine.getOptions();
    opt.render.stereo = true;
    opt.render.effect.antialiasing.enable = true;
    opt.render.effect.antialiasing.mode = "ssaa";
    opt.render.effect.tone_mapping = true;
    opt.render.hdri.ambient = true;
    engine.getScene().add(argv[3]);
    f3d::window& window = engine.getWindow();
    // the pair of a thumbnail keeps its own angle, 2 degrees as in +stereo3d1, by the route of images (not an option): an image has no
    // window whose depth limits could give one, and the depth of a thumbnail has no recorded design yet (Daniel's call)
    window.setStereoImageEyeAngle(2.0);
    window.setSize(size / 2, size / 2);
    f3d::camera& camera = window.getCamera();
    camera.resetToBounds();
    camera.azimuth(-45).elevation(26.5).resetToBounds();
    f3d::image image = window.renderToImage(true);
    const std::vector<unsigned char> png =
      withText(image.saveBuffer(f3d::image::SaveFormat::PNG), "X-KDE::Stereo3DLayout", "sideBySideLeftFirst");
    std::ofstream out(argv[4], std::ios::binary);
    out.write(reinterpret_cast<const char*>(png.data()), static_cast<std::streamsize>(png.size()));
    if (!out)
    {
      throw std::runtime_error("cannot write the thumbnail");
    }
  }
  catch (const std::exception& e)
  {
    std::cerr << "f3d-thumbnail-pair: " << argv[3] << ": " << e.what() << std::endl;
    return 1;
  }
  return 0;
}
