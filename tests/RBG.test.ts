import { describe, it, expect, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const daoMember1 = accounts.get("wallet_1")!;
const daoMember2 = accounts.get("wallet_2")!;
const nonDaoMember = accounts.get("wallet_3")!;

// Mocking the DAO state and contract functions
type DAOState = {
  userReputation: Map<string, number>;
  proposals: Map<number, any>;
  proposalCount: number;
};

let daoState: DAOState;

// Helper function to reset the DAO state
const resetDAOState = () => {
  daoState = {
    userReputation: new Map(),
    proposals: new Map(),
    proposalCount: 0,
  };
};

// Contract functions to test
const initializeReputation = (user: string) => {
  daoState.userReputation.set(user, 100); // Initialize user reputation with 100
};

const createProposal = (creator: string, title: string, blocks: number) => {
  const userRep = daoState.userReputation.get(creator) || 0;
  if (userRep < 100) {
    return { error: "Insufficient reputation" };
  }

  const newId = daoState.proposalCount + 1;
  daoState.proposals.set(newId, {
    title: title,
    creator: creator,
    votesFor: 0,
    votesAgainst: 0,
    status: "active",
    endBlock: blocks + 10, // Simplified block height
  });
  daoState.proposalCount = newId;

  return { proposalId: newId };
};

const vote = (user: string, proposalId: number, voteFor: boolean) => {
  const userRep = daoState.userReputation.get(user) || 0;
  const proposal = daoState.proposals.get(proposalId);
  if (userRep <= 0) {
    return { error: "No reputation" };
  }
  if (proposal.status !== "active") {
    return { error: "Proposal not active" };
  }
  if (proposal.endBlock <= 10) { // Simplified check for proposal end
    return { error: "Proposal has ended" };
  }

  if (voteFor) {
    proposal.votesFor += userRep;
  } else {
    proposal.votesAgainst += userRep;
  }

  return { success: true };
};

// Tests using Vitest
describe("Reputation-Based DAO Governance Contract", () => {
  beforeEach(() => {
    // Reset the DAO state before each test
    resetDAOState();
  });

  it("should allow initializing user reputation", () => {
    initializeReputation(daoMember1);

    const reputation = daoState.userReputation.get(daoMember1);
    expect(reputation).toBe(100);
  });

  it("should allow creating a proposal for eligible users", () => {
    initializeReputation(daoMember1);

    const result = createProposal(daoMember1, "New Proposal", 5);
    expect(result.proposalId).toBeGreaterThan(0);
  });

  it("should allow voting on a proposal", () => {
    initializeReputation(daoMember1);
    const result = createProposal(daoMember1, "New Proposal", 5);

    if (result.proposalId !== undefined) {
      const voteResult = vote(daoMember1, result.proposalId, true);
      expect(voteResult.success).toBe(true);
    } else {
      throw new Error("Proposal creation failed");
    }
  });
  it("should reject voting for users with no reputation", () => {
    initializeReputation(daoMember1);
    const result = createProposal(daoMember1, "New Proposal", 5);

    if (result.proposalId !== undefined) {
      const voteResult = vote(nonDaoMember, result.proposalId, true);
      expect(voteResult.error).toBe("No reputation");
    } else {
      throw new Error("Proposal creation failed");
    }
  });

  it("should reject voting on inactive proposals", () => {
    initializeReputation(daoMember1);
    const result = createProposal(daoMember1, "New Proposal", 5);

    if (result.proposalId !== undefined) {
      // Simulating end of proposal
      daoState.proposals.get(result.proposalId).status = "inactive";

      const voteResult = vote(daoMember1, result.proposalId, true);
      expect(voteResult.error).toBe("Proposal not active");
    } else {
      throw new Error("Proposal creation failed");
    }
  });
  it("should reject voting after proposal end", () => {
    initializeReputation(daoMember1);
    const result = createProposal(daoMember1, "New Proposal", 5);

    if (result.proposalId !== undefined) {
      // Simulating proposal expiration
      daoState.proposals.get(result.proposalId).endBlock = 5;

      const voteResult = vote(daoMember1, result.proposalId, true);
      expect(voteResult.error).toBe("Proposal has ended");
    } else {
      throw new Error("Proposal creation failed");
    }
  });

  it("should update the votes correctly after voting", () => {
    initializeReputation(daoMember1);
    const result = createProposal(daoMember1, "New Proposal", 5);

    if (result.proposalId !== undefined) {
      vote(daoMember1, result.proposalId, true);

      const proposal = daoState.proposals.get(result.proposalId);
      expect(proposal.votesFor).toBe(100); // User reputation is 100
    } else {
      throw new Error("Proposal creation failed");
    }
  });
});
