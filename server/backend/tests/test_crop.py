from io import BytesIO
import pytest
from PIL import Image
from backend.app.config import MEDIA
from backend.app.crop import crop_image
from backend.app.image_features import InvalidImage


def test_crop_restricts_source_image_and_changes_pixels():
    data = (MEDIA / 'p02.jpg').read_bytes()
    assert crop_image(data, '') == data
    cropped = crop_image(data, '.20,.20,.50,.50')
    with Image.open(BytesIO(data)) as original, Image.open(BytesIO(cropped)) as result:
        assert result.width < original.width
        assert result.height < original.height
        assert result.format == 'JPEG'


@pytest.mark.parametrize('bad', ['-0.1,0,.4,.4','0,0,1.5,1','0,0,.01,.01','junk','0,0,0,0','0,0,.4'])
def test_bad_crops_rejected(bad):
    with pytest.raises(InvalidImage):
        crop_image((MEDIA / 'p01.jpg').read_bytes(), bad)
