import { ImageResponse } from "next/og";

export const size = {
  width: 180,
  height: 180
};

export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          borderRadius: 42,
          background: "linear-gradient(180deg, #C96D42 0%, #126A4A 100%)",
          color: "#FFF9F1",
          fontSize: 76,
          fontWeight: 800
        }}
      >
        TS
      </div>
    ),
    size
  );
}

