#!/usr/bin/env python3
import os
import random
import hashlib
import pydicom
import numpy as np
from PIL import Image
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import ExplicitVRLittleEndian, generate_uid
import json
import argparse

def calculate_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def create_folders(base_path, identifier):
    dataset_path = os.path.join(base_path, f"DATASET_{identifier}")
    folders = [
        "METADATA",
        "IMAGES",
        "ANNOTATIONS",
        "LANDING_PAGE/THUMBNAILS",
        "PRIVATE"
    ]

    for folder in folders:
        os.makedirs(os.path.join(dataset_path, folder), exist_ok=True)
    return dataset_path

def create_dicom_image(images_dir, identifier, image_size_mb):
    images_data = []

    for i in range(1, 3):
        image_alias = f"image_{i}_{identifier}"
        subfolder_rel = f"IMAGE_{image_alias}"
        subfolder_abs = os.path.join(images_dir, subfolder_rel)
        os.makedirs(subfolder_abs, exist_ok=True)

        image_size = (512, 512)
        # Cap slices at a maximum of 9
        calculated_slices = int((image_size_mb * 1024 * 1024) / (512 * 512))
        num_slices = min(9, max(1, calculated_slices))
        pixel_array = np.random.randint(0, 256, size=image_size, dtype=np.uint8)

        files = []
        for j in range(num_slices):
            file_meta = Dataset()
            file_meta.MediaStorageSOPClassUID = "1.2.840.10008.5.1.4.1.1.7"
            file_meta.MediaStorageSOPInstanceUID = generate_uid()
            file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

            slice_filename = f"slice_{j}.dcm"
            dcm_file = os.path.join(subfolder_abs, slice_filename)
            ds = FileDataset(dcm_file, {}, file_meta=file_meta, preamble=b"\0" * 128)
            ds.is_little_endian = True
            ds.is_implicit_VR = False

            ds.PatientName = "Test^Patient"
            ds.PatientID = "12345"
            ds.Modality = "OT"
            ds.Rows, ds.Columns = image_size
            ds.PhotometricInterpretation = "MONOCHROME2"
            ds.SamplesPerPixel = 1
            ds.BitsAllocated = 8
            ds.BitsStored = 8
            ds.HighBit = 7
            ds.PixelRepresentation = 0
            ds.PixelData = pixel_array.tobytes()

            ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
            ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID

            ds.save_as(dcm_file, write_like_original=False)

            checksum = calculate_sha256(dcm_file)
            xml_path = f"IMAGES/{subfolder_rel}/{slice_filename}"
            files.append({
                "filename": xml_path,
                "checksum": checksum
            })

        images_data.append({
            "alias": image_alias,
            "files": files
        })

    return images_data

def create_geojson(annotations_path):
    geojson_data = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [random.uniform(-180, 180), random.uniform(-90, 90)]
            },
            "properties": {"name": "Annotation 1"}
        }]
    }
    file_abs = os.path.join(annotations_path, "test.geojson")
    with open(file_abs, "w") as f:
        json.dump(geojson_data, f, indent=4)

    checksum = calculate_sha256(file_abs)
    return {
        "filename": "ANNOTATIONS/test.geojson",
        "checksum": checksum
    }

def create_xml_files(metadata_path, identifier, images_data, annotation_info):
    # dataset.xml
    dataset_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<DATASET_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <DATASET alias="{identifier}">
        <TITLE>Dummy Dataset {identifier}</TITLE>
        <SHORT_NAME>{identifier}</SHORT_NAME>
        <DESCRIPTION>Automated test dataset for Big Picture project validation.</DESCRIPTION>
        <VERSION>1.0</VERSION>
        <METADATA_STANDARD>2.0.0</METADATA_STANDARD>
        <ATTRIBUTES xsi:nil="true" />
    </DATASET>
</DATASET_SET>
"""
    with open(os.path.join(metadata_path, "dataset.xml"), "w") as f:
        f.write(dataset_xml)

    # policy.xml
    policy_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<POLICY_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	<POLICY alias="POLICY_{identifier}">
		<DATASET_REF alias="{identifier}"></DATASET_REF>
		<ATTRIBUTES>
			<STRING_ATTRIBUTE>
				<TAG>title</TAG>
				<VALUE>N/A</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>policy_text</TAG>
				<VALUE>N/A</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>type_of_dataset</TAG>
				<VALUE>Non-Clinical / Cryptonimized</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>terms_of_use_version</TAG>
				<VALUE>2026-07-29T14:12:08.862948</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>allowed_geographical_distribution</TAG>
				<VALUE>European Union and EEA countries</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>duration_of_use</TAG>
				<VALUE>Limited to the duration of the purpose of the data access request</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>defined_research_question_required</TAG>
				<VALUE>True</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>type_of_access</TAG>
				<VALUE>Direct access</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>required_bigpicture_acknowledgements</TAG>
				<VALUE>”This project has received funding from the Innovative Medicines Initiative 2 Joint Undertaking under grant agreement No 945358. This Joint Undertaking receives support from the European Union’s Horizon 2020 research and innovation program and EFPIA”</VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>legal_basis_for_sharing_the_data</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>informed_consent_form_defined_use_restrictions</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</STRING_ATTRIBUTE>
			<STRING_ATTRIBUTE>
				<TAG>custom_use_restrictions</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</STRING_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>allowed_uses</TAG>
				<VALUE>
					<STRING_ATTRIBUTE>
						<TAG>allowed_use</TAG>
						<VALUE>Implementation of Bigpicture Project (IMI2-945358)</VALUE>
					</STRING_ATTRIBUTE>
				</VALUE>
			</SET_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>required_custom_acknowledgements</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</SET_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>required_citations</TAG>
				<VALUE>
					<STRING_ATTRIBUTE>
						<TAG>citation</TAG>
						<VALUE>N/A</VALUE>
					</STRING_ATTRIBUTE>
				</VALUE>
			</SET_ATTRIBUTE>
			<SET_ATTRIBUTE>
				<TAG>licenses</TAG>
				<VALUE xsi:nil="true"></VALUE>
			</SET_ATTRIBUTE>
		</ATTRIBUTES>
	</POLICY>
</POLICY_SET>
"""
    with open(os.path.join(metadata_path, "policy.xml"), "w") as f:
        f.write(policy_xml)

    # sample.xml
    sample_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<SAMPLE_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <BIOLOGICAL_BEING alias="being_{identifier}">
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </BIOLOGICAL_BEING>
    <CASE alias="case_{identifier}">
        <BIOLOGICAL_BEING_REF alias="being_{identifier}"/>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </CASE>
    <SPECIMEN alias="specimen_{identifier}">
        <EXTRACTED_FROM_REF alias="being_{identifier}"/>
        <PART_OF_CASE_REF alias="case_{identifier}"/>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </SPECIMEN>
    <BLOCK alias="block_{identifier}">
        <SAMPLED_FROM_REF alias="specimen_{identifier}"/>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </BLOCK>
    <SLIDE alias="slide_{identifier}">
        <CREATED_FROM_REF alias="block_{identifier}"/>
        <STAINING_INFORMATION_REF alias="staining_{identifier}"/>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </SLIDE>
</SAMPLE_SET>
"""
    with open(os.path.join(metadata_path, "sample.xml"), "w") as f:
        f.write(sample_xml)

    # image.xml
    image_entries = []
    for img in images_data:
        file_nodes = []
        for file in img["files"]:
            file_nodes.append(
                f'            <FILE filename="{file["filename"]}" checksum_method="SHA256" '
                f'checksum="{file["checksum"]}" unencrypted_checksum="{file["checksum"]}" filetype="dcm"/>'
            )
        files_xml = os.linesep.join(file_nodes)

        image_entries.append(f"""    <IMAGE alias="{img['alias']}">
        <IMAGE_OF alias="slide_{identifier}"/>
        <IMAGE_TYPE>
            <WSI_IMAGE>test</WSI_IMAGE>
        </IMAGE_TYPE>
        <FILES>
{files_xml}
        </FILES>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </IMAGE>""")

    image_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<IMAGE_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
{os.linesep.join(image_entries)}
</IMAGE_SET>
"""
    with open(os.path.join(metadata_path, "image.xml"), "w") as f:
        f.write(image_xml)

    # annotation.xml
    first_image_alias = images_data[0]["alias"]
    annotation_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<ANNOTATION_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <ANNOTATION alias="annotation_{identifier}">
        <IMAGE_REF alias="{first_image_alias}"/>
        <FILES>
            <FILE filename="{annotation_info['filename']}" checksum_method="SHA256" checksum="{annotation_info['checksum']}" filetype="json"/>
        </FILES>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </ANNOTATION>
</ANNOTATION_SET>
"""
    with open(os.path.join(metadata_path, "annotation.xml"), "w") as f:
        f.write(annotation_xml)

    # observer.xml
    observer_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<OBSERVER_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <OBSERVER alias="observer_{identifier}">
        <OBSERVER_TYPE>Human</OBSERVER_TYPE>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </OBSERVER>
</OBSERVER_SET>
"""
    with open(os.path.join(metadata_path, "observer.xml"), "w") as f:
        f.write(observer_xml)

    # observation.xml
    observation_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<OBSERVATION_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <OBSERVATION alias="observation_{identifier}">
        <ANNOTATION_REF alias="annotation_{identifier}"/>
        <OBSERVER_REF alias="observer_{identifier}"/>
        <STATEMENT>
            <STATEMENT_TYPE>Diagnosis</STATEMENT_TYPE>
            <STATEMENT_STATUS>Summary</STATEMENT_STATUS>
            <CODE_ATTRIBUTES>
                <CODE_ATTRIBUTE>
                    <TAG>test</TAG>
                    <VALUE>
                        <CODE>test</CODE>
                        <SCHEME>test</SCHEME>
                        <MEANING>test</MEANING>
                        <SCHEME_VERSION>1.0</SCHEME_VERSION>
                    </VALUE>
                </CODE_ATTRIBUTE>
            </CODE_ATTRIBUTES>
            <CUSTOM_ATTRIBUTES>
                <STRING_ATTRIBUTE>
                    <TAG>test</TAG>
                    <VALUE>test</VALUE>
                </STRING_ATTRIBUTE>
            </CUSTOM_ATTRIBUTES>
            <FREETEXT>test</FREETEXT>
            <ATTRIBUTES xsi:nil="true"/>
        </STATEMENT>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </OBSERVATION>
</OBSERVATION_SET>
"""
    with open(os.path.join(metadata_path, "observation.xml"), "w") as f:
        f.write(observation_xml)

    # staining.xml
    staining_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<STAINING_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <STAINING alias="staining_{identifier}">
        <PROCEDURE_INFORMATION>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </PROCEDURE_INFORMATION>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </STAINING>
</STAINING_SET>
"""
    with open(os.path.join(metadata_path, "staining.xml"), "w") as f:
        f.write(staining_xml)

def create_landing_page(landing_page_path, identifier):
    thumbnail_path = os.path.join(landing_page_path, "THUMBNAILS")

    thumb_rel_path = "LANDING_PAGE/THUMBNAILS/thumbnail_0.jpg"
    first_thumb_hash = ""

    for i in range(3):
        img = Image.fromarray(np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8))
        thumb_abs = os.path.join(thumbnail_path, f"thumbnail_{i}.jpg")
        img.save(thumb_abs)
        if i == 0:
            first_thumb_hash = calculate_sha256(thumb_abs)

    landing_page_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<LANDING_PAGE_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <LANDING_PAGE alias="landing_page_{identifier}">
        <DATASET_REF alias="{identifier}" />
        <SAMPLE_IMAGE_FILES>
            <SAMPLE_IMAGE_FILE filename="{thumb_rel_path}" checksum_method="SHA256" checksum="{first_thumb_hash}" unencrypted_checksum="{first_thumb_hash}" filetype="jpg" />
        </SAMPLE_IMAGE_FILES>
        <ATTRIBUTES xsi:nil="true" />
    </LANDING_PAGE>
</LANDING_PAGE_SET>
"""
    with open(os.path.join(landing_page_path, "landing_page.xml"), "w") as f:
        f.write(landing_page_xml)

def create_private_files(private_path, identifier, create_datacite=True):
    org_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<ORGANISATION_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <ORGANISATION alias="org_{identifier}">
        <NAME>Test Organization</NAME>
        <PIC_CODE>123456789</PIC_CODE>
        <DATAMANAGER_PERUN_GROUP>perun_group_dummy</DATAMANAGER_PERUN_GROUP>
        <DATASET_REF alias="{identifier}" />
        <ATTRIBUTES xsi:nil="true" />
    </ORGANISATION>
</ORGANISATION_SET>
"""
    with open(os.path.join(private_path, "organisation.xml"), "w") as f:
        f.write(org_xml)

    rems_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<REMS_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <REMS alias="rems_{identifier}">
        <WORKFLOW_ID>1</WORKFLOW_ID>
        <ORGANISATION_ID>demo</ORGANISATION_ID>
        <DATASET_REF alias="{identifier}"/>
        <ATTRIBUTES>
            <STRING_ATTRIBUTE>
                <TAG>test</TAG>
                <VALUE>test</VALUE>
            </STRING_ATTRIBUTE>
        </ATTRIBUTES>
    </REMS>
</REMS_SET>
"""
    with open(os.path.join(private_path, "rems.xml"), "w") as f:
        f.write(rems_xml)

    if create_datacite:
        datacite_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<resource xmlns="http://datacite.org/schema/kernel-4">
    <identifier identifierType="DOI">10.1234/example.doi.{identifier}</identifier>
    <creators>
        <creator>
            <creatorName nameType="Personal">Smith, John</creatorName>
            <givenName>John</givenName>
            <familyName>Smith</familyName>
            <nameIdentifier nameIdentifierScheme="ORCID" schemeURI="https://orcid.org">https://orcid.org/0000-0002-1825-0097</nameIdentifier>
            <affiliation affiliationIdentifier="https://ror.org/00fnk0q46" affiliationIdentifierScheme="ROR" schemeURI="https://www.ror.org/">Academy of Medicine</affiliation>
        </creator>
    </creators>
    <publisher publisherIdentifier="https://ror.org/01pbevv174" publisherIdentifierScheme="ROR" schemeURI="https://ror.org/">Attogen Biomedical Research</publisher>
    <contributors>
        <contributor contributorType="DataManager">
            <contributorName nameType="Personal">Doe, Jane</contributorName>
            <givenName>Jane</givenName>
            <familyName>Doe</familyName>
        </contributor>
    </contributors>
    <titles>
        <title>Sample Dataset {identifier}</title>
    </titles>
    <publicationYear>2026</publicationYear>
    <version>1.0</version>
    <resourceType resourceTypeGeneral="Dataset">Dataset</resourceType>
    <rightsList>
        <rights rightsIdentifier="cc-by-4.0" rightsIdentifierScheme="SPDX" schemeURI="https://spdx.org/licenses/" rightsURI="https://creativecommons.org/licenses/by/4.0/legalcode">Creative Commons Attribution 4.0 International</rights>
    </rightsList>
    <subjects>
        <subject subjectScheme="OKM Ontology" schemeURI="http://www.yso.fi/onto/okm-tieteenala/conceptscheme" valueURI="http://www.yso.fi/onto/okm-tieteenala/ta6122" classificationCode="6122">Literature studies</subject>
    </subjects>
    <dates>
        <date dateType="Created">2026-01-01</date>
        <date dateType="Updated" dateInformation="Metadata updated">2026-01-01</date>
    </dates>
    <language>en</language>
    <alternateIdentifiers>
        <alternateIdentifier alternateIdentifierType="LocalID">{identifier}</alternateIdentifier>
    </alternateIdentifiers>
    <sizes>
        <size>1GB</size>
    </sizes>
    <formats>
        <format>application/octet-stream</format>
    </formats>
    <descriptions>
        <description descriptionType="Abstract" xml:lang="en">This is an automated sample test dataset for dataset identifier {identifier}.</description>
    </descriptions>
</resource>
"""
        with open(os.path.join(private_path, "datacite.xml"), "w") as f:
            f.write(datacite_xml)

def create_dataset(base_path, identifier, image_size_mb, create_datacite=True):
    dataset_path = create_folders(base_path, identifier)

    images_data = create_dicom_image(os.path.join(dataset_path, "IMAGES"), identifier, image_size_mb)
    annotation_info = create_geojson(os.path.join(dataset_path, "ANNOTATIONS"))

    create_xml_files(os.path.join(dataset_path, "METADATA"), identifier, images_data, annotation_info)
    create_landing_page(os.path.join(dataset_path, "LANDING_PAGE"), identifier)
    create_private_files(os.path.join(dataset_path, "PRIVATE"), identifier, create_datacite=create_datacite)

    print(f"Dataset successfully created at: {dataset_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create Big Picture dummy dataset folder structure")
    parser.add_argument("identifier", type=str, help="Dataset identifier")
    parser.add_argument("--image-size", type=int, default=10, help="Size of image files in MB (default: 10MB)")
    parser.add_argument("--no-datacite", action="store_true", help="Skip creating PRIVATE/datacite.xml")
    args = parser.parse_args()

    create_dataset("./", args.identifier, args.image_size, create_datacite=not args.no_datacite)