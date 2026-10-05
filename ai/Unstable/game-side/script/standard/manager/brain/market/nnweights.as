namespace Market {

// The value net's weights. This repo copy is the empty net: tools/nntrain.py
// overwrites the DEPLOYED copy between games, so each game loads the latest.
const bool NNW_ON = false;
const int NNW_GAMES = 0;
const string NNW_STATE = "";
const array<string> NNW_KINDS = {};
const int NNW_S = 0;
const int NNW_O = 0;
const int NNW_H = 0;
const array<float> NNW_XM = {};
const array<float> NNW_XS = {};
const array<float> NNW_W1 = {};
const array<float> NNW_B1 = {};
const array<float> NNW_W2 = {};
const array<float> NNW_B2 = {};
const array<float> NNW_WO = {};
const float NNW_BO = 0.f;
const array<float> NNW_TRUST = {};
// the factory net (production.as roulette)
const bool NNF_ON = false;
const string NNF_STATE = "";
const int NNF_S = 0;
const int NNF_O = 0;
const int NNF_H = 0;
const array<float> NNF_XM = {};
const array<float> NNF_XS = {};
const array<float> NNF_W1 = {};
const array<float> NNF_B1 = {};
const array<float> NNF_W2 = {};
const array<float> NNF_B2 = {};
const array<float> NNF_WO = {};
const float NNF_BO = 0.f;
const float NNF_TRUST = 0.f;
// the BARb imitation prior (tools/imitate.py): P(class of BARb's next structure | state)
const bool NNI_ON = false;
const string NNI_FEATURES = "";
const string NNI_CLASSES = "";
const int NNI_F = 0;
const int NNI_C = 0;
const int NNI_H = 0;
const array<float> NNI_XM = {};
const array<float> NNI_XS = {};
const array<float> NNI_W1 = {};
const array<float> NNI_B1 = {};
const array<float> NNI_W2 = {};
const array<float> NNI_B2 = {};
const array<float> NNI_W3 = {};
const array<float> NNI_B3 = {};
// the posture net (military/nnpost.as); NNP_STATE = NN_STATE + "|" + the posture fields
const bool NNP_ON = false;
const string NNP_STATE = "";
const int NNP_S = 0;
const int NNP_O = 0;
const int NNP_H = 0;
const array<float> NNP_XM = {};
const array<float> NNP_XS = {};
const array<float> NNP_W1 = {};
const array<float> NNP_B1 = {};
const array<float> NNP_W2 = {};
const array<float> NNP_B2 = {};
const array<float> NNP_WO = {};
const float NNP_BO = 0.f;
const float NNP_TRUST = 0.f;

}  // namespace Market
