import { ImageResponse } from "next/og";

export const size = {
  width: 512,
  height: 512
};

export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(180deg, #126A4A 0%, #11261D 100%)",
          color: "#FFF9F1",
          fontSize: 220,
          fontWeight: 800
        }}
      >
        TS
      </div>
    ),
    size
  );
}

