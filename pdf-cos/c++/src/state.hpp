#pragma once

#include <map>
#include <tuple>
#include <variant>
#include <unordered_set>
#include <optional>

#include "main_parser.h"
#include <ddl/input.h>
#include <ddl/owned.h>
#include "encryption.hpp"

struct Blackhole {};

struct StreamThunk {
    uint64_t container;
    uint64_t index;
    explicit StreamThunk(uint64_t container, uint64_t index);

    bool getDecl(uint64_t refid, User::TopDecl *result);
};

struct TopThunk {
    uint64_t offset;

public:
    explicit TopThunk(uint64_t offset);

    // Borrows: this, input
    // Populates owned result
    // Returns true on success
    bool getDecl(DDL::Input input, User::TopDecl *result);
};

using oref = std::variant<
    Blackhole,
    TopThunk,
    StreamThunk,
    DDL::Owned<User::TopDecl>
>;

using generation_type = uint16_t;

struct ReferenceEntry {
    ReferenceEntry(oref value, generation_type gen);
    oref value;
    generation_type gen;
};


class ReferenceTable {

private:
    std::optional<DDL::Owned<DDL::Input>> topinput;
    std::optional<EncryptionContext> encCtx;
    std::optional<DDL::Owned<User::Ref>> root;

    void process_xref(std::unordered_set<size_t>*, DDL::Input, DDL::Size, bool top);
    void process_oldXRef(std::unordered_set<size_t>*, DDL::Input, User::CrossRefAndTrailer, bool top);
    void process_newXRef(std::unordered_set<size_t>*, DDL::Input, User::XRefObjTable, bool top);
    void process_trailer(std::unordered_set<size_t>*, DDL::Input, User::TrailerDict);
    void process_trailer_post(User::TrailerDict);
    void register_uncompressed_reference(uint64_t refid, generation_type gen, uint64_t offset);
    void register_compressed_reference(uint64_t refid, uint64_t container, uint64_t index);
    void register_topdecl(uint64_t refid, generation_type gen, User::TopDecl topDecl);
    void unregister(uint64_t refid);

public: // temporarily public member
    std::map<uint64_t, ReferenceEntry> table;

    uint64_t currentObjId;
    generation_type currentGen;

public:
    std::optional<EncryptionContext> const& getEncryptionContext() const;

    bool resolve_reference(uint64_t refid, generation_type gen, DDL::Maybe<User::TopDecl> *result);

    std::optional<DDL::Owned<User::Ref>> const& getRoot() const;
    
    // owns input
    void process_pdf(DDL::Input);
};

extern ReferenceTable references;

struct XrefException : public std::exception {
    const char * msg;
    XrefException(const char *msg) : msg(msg) {}
    const char * what () const throw () override
    {
        return msg;
    }
};
