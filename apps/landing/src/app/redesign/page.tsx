import type { ReactElement } from "react";
import { RedesignNav } from "../../components/redesign/RedesignNav";
import { RedesignHero } from "../../components/redesign/RedesignHero";
import { RedesignProof } from "../../components/redesign/RedesignProof";
import { RedesignFeatures } from "../../components/redesign/RedesignFeatures";
import { RedesignWorkflow } from "../../components/redesign/RedesignWorkflow";
import { RedesignArchitecture } from "../../components/redesign/RedesignArchitecture";
import { RedesignCTA } from "../../components/redesign/RedesignCTA";
import { RedesignFooter } from "../../components/redesign/RedesignFooter";
import { MotionObserver } from "../../components/redesign/MotionObserver";
import { ScrollProgress } from "../../components/redesign/ScrollProgress";

const docsUrl = "https://docs.openrecorder.xyz/";
const sourceUrl = "https://github.com/imbhargav5/open-recorder";

export default function RedesignPage(): ReactElement {
  return (
    <main>
      {/* Client components — mount silently */}
      <ScrollProgress />
      <MotionObserver />

      <RedesignNav />
      <RedesignHero docsUrl={docsUrl} sourceUrl={sourceUrl} />
      <RedesignProof />
      <RedesignFeatures />
      <RedesignWorkflow />
      <RedesignArchitecture />
      <RedesignCTA sourceUrl={sourceUrl} />
      <RedesignFooter />
    </main>
  );
}
