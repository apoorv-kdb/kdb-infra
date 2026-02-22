import './SelectDropdown.scss';

interface Option {
  label: string;
  value: string;
}

interface SelectDropdownProps {
  label:    string;
  options:  Option[];
  value:    string;
  onChange: (value: string) => void;
}

// Simple single-select — uses native <select> for simplicity.
// No need for a custom dropdown here since only one value
// is ever selected and there are only 4 options.

const SelectDropdown = ({ label, options, value, onChange }: SelectDropdownProps) => {
  return (
    <div className="select-dropdown">
      <label className="select-dropdown__label">{label}</label>
      <select
        className="select-dropdown__select"
        value={value}
        onChange={e => onChange(e.target.value)}
      >
        {options.map(opt => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
};

export default SelectDropdown;
