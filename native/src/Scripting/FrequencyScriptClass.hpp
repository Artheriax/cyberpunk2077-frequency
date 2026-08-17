#ifndef FREQUENCY_SCRIPT_CLASS_HPP
#define FREQUENCY_SCRIPT_CLASS_HPP

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>

namespace Frequency
{

/// Native scripting class exposed to CET as `Frequency`.
/// All functions on it are static; the class carries no instance state.
struct FrequencyScriptClass : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType();
};

/// RTTI descriptor for the class above.
inline RED4ext::TTypedClass<FrequencyScriptClass> g_frequencyClass("Frequency");

inline RED4ext::CClass* FrequencyScriptClass::GetNativeType()
{
    return &g_frequencyClass;
}

} // namespace Frequency

#endif // FREQUENCY_SCRIPT_CLASS_HPP
