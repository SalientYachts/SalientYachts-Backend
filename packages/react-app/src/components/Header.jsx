import { PageHeader } from "antd";
import React from "react";

// displays a page header

export default function Header() {
  return (
    <PageHeader
      title="⛵ Salient Yachts"
      subTitle="A yacht NFT that rewards its owners"
      style={{ cursor: "pointer" }}
    />
  );
}
